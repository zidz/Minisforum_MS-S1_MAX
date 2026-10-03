#!/bin/bash
# halogen-flash-server 0.16.0 — Qwen3.8-Flash-Next UD-Q4_K_XL på port 8080
#
# Ersätter llama.cpp/Vulkan-servern med Qwen3.8-27B. ROCm/HIP-motorn kör på
# amdgpu/KFD-stacken, inte Vulkan — därför är --device=/dev/kfd obligatoriskt
# utöver /dev/dri. Kräver kernel 7.0+ (vi kör 7.0.0-34-generic).
#
# Minnesbudget på den här burken (124,45 GiB MemTotal, varav 1,0 GiB är
# firmware-carve-out för iGPU:n som aldrig syns i /proc/meminfo):
#   vikter UD-Q4_K_XL  79,6 GiB  pinnade
#   vision tower        0,8 GiB  pinnad
#   pool 262144         7,2 GiB
#   working mem @16384 11,2 GiB
#   ------------------------------------
#   halogen tar        ~98 GiB, ~7,8 GiB lämnas till allt annat vid start
#   (buff/cache som blir över är lookup-tablens page cache — motorn läser
#    26,8 GiB-tabben därifrån, så den är INTE "ledigt minne")
#
# HALOGEN_HOST_RESERVE_GIB är 16, inte mer. Värdet dras AV budgeten vid
# startens fit-kontroll, så att höja det gör servern mindre, inte mer
# konservativ. 16 är vad som faktiskt täcker Qwen3-Embedding-8B på 8081.
#
# HALOGEN_CTX + HALOGEN_KV_POOL_POSITIONS är båda 262144, modellens fulla
# fönster. Motorn kräver att poolen är minst lika stor som kontextfönstret
# ("--kv-pool 196608: at least --ctx 262144") — de måste flyttas tillsammans.
# 262144 var det som headeren alltid påstod, men 0.15.0 kunde inte starta
# med det: 0.15.1-fixen satt working memory ~8 GiB för högt vid startens
# fit-kontroll. På 0.16.0 går det rent (7,2 GiB pool, 98,8 GiB totalt).
# Observerad kostnad: 262144 lämnar 7,8 GiB hostminne mot 9,4 GiB på
# 196608 — precis under motorns ~10 GiB-varning för lookup-tablens
# page cache. Mätt på 6000-tokens prefill: 1269 t/s @262144 mot
# 1319 t/s @196608 (~4% långsammare). Vinsten är att poolen inte längre
# trycks till 100% och att svar inte klipps ("max_tokens clamped").
# max_tokens_cap lämnas på image-default 65536 (opencodes output-tak är
# också 65536, så capen är aldrig flaskhalsen — det var poolen det).
#
# Alternativ som är avsiktligt AVstängda:
#  -e HALOGEN_FLASH_PIN_TRUNK=0 \
#    Gäller bara w4b; v2 vägrar det vid start. Flera gånger sämre decode.
#  -e HALOGEN_WEIGHTS_LOCK=1 \
#    Kräver memlock hard limit = unlimited. Vår är 15,5 GiB.
#
# VISION — PÅ, och det var tight:
#   HALOGEN_VISION_TOWER=1 lägger till 0,84 GiB som *pinnas*. Motorn vägrar
#   att pina under 16,0 GiB MemAvailable ("the floor is 16.00 GiB"), och den
#   flooren är HÅRD — den rör sig inte med HALOGEN_HOST_RESERVE_GIB (testat med
#   reserve 12: flooren var fortfarande 16.00). Utan vision startar samma
#   config med 2,8 GiB mindre på kontot; med vision startar den bara om
#   embedding-containern är liten nog. Se nästa stycke.
#   VARNING: sätt värdet till 0 är värre än att inte sätta det — "0" är inte
#   giltigt och entrypointen hänger då tyst på en prompt utan TTY.
#
# VARFÖR embedding-containern är nedkrympt till -c 8192 / -b 4096 / -ub 4096:
#   Den är co-tenant och håller ~13,2 GiB GTT (= värdeminne). Med -c 32768
#   låg halogen antingen 2,8 GiB *under* pinn-golvet och vägrade starta, eller
#   startade i en crash-loop med --restart (se halogens egen varning: en task
#   som väntar på pinnade sidor kan inte avlivas, så 12 omstarter lämnade burken
#   i 14 GiB tillgängligt). Med -c 8192 sparar den ~1,9 GiB GTT och boxen har
#   13,2 GiB kvar vid start. 8192 räcker långt för a0:s chunkar.
#   Embedding-uttaget mättes efteråt: 4096-dim, norm 1.0, korrekt.

# Säkerställ att sökvägen till modellerna är absolut
MODEL_DIR="$(pwd)/models"
# Dynamisk hämtning av det numeriska ID:t för render-gruppen
RENDER_GID=$(getent group render | cut -d: -f3)

echo "Startar halogen-flash-server (Qwen3.8-Flash-Next UD-Q4_K_XL) i Docker..."

# 1. Stoppa den gamla huvudmodellen. 27B-containern håller ~54 GiB GTT som
#    halogen annars inte får plats med.
docker rm -f llama-server-qwen-first-vulkan 2>/dev/null

# 2. Gör omkörningar idempotenta.
docker rm -f halogen-flash-server 2>/dev/null

# 2b. Vision-sideloaden hämtas INTE av entrypointen, även med HALOGEN_DOWNLOAD
#     satt — den hämtar bara draft head + tokenizer. Utan filen startar
#     servern i en crash-loop ("no sidecar at ..."), och med
#     --restart unless-stopped går den då i oändlig omstart.
VISION_FILE="${MODEL_DIR}/unsloth/Qwen3.8-Flash-Next-GGUF/UD-Q4_K_XL/qwen38-flash-next-vision.hgn"
if [ ! -f "${VISION_FILE}" ]; then
  echo "[*] Vision-sideload saknas, laddar ner 0,84 GiB..."
  docker run --rm -e HF_HUB_OFFLINE=0 -v "${MODEL_DIR}:/models" --entrypoint hf \
    ghcr.io/peonist-ai/halogen-flash-server:0.16.0 \
    download peonist-ai/halogen-qwen3.8-flash-next qwen38-flash-next-vision.hgn \
    --local-dir /models/unsloth/Qwen3.8-Flash-Next-GGUF/UD-Q4_K_XL
fi

# 3. Vänta ut den gamla arenan INNAN preflight. Motorns pinn-golv är 16,0 GiB
#    MemAvailable, och en task som väntar på pinnade sidor kan inte avlivas —
#    den gamla motorn håller ~96 GiB i upp till en halv minut efter att
#    containern är borttagen. Utan den här väntan mäter varje försök en sämre
#    maskin än det föregående, vilket är precis hur 12 omstarter i rad
#    lämnade burken med 14 GiB tillgängligt i stället för 109.
echo "[*] Väntar ut eventuell gammal motor..."
while pgrep flash_serve >/dev/null 2>&1; do sleep 3; done

# 4. Preflight,EFTERSOM teardown är klar och före start. Motorn vägrar pina
#    under 16,0 GiB MemAvailable ("the floor is 16.00 GiB") — en HÅRD gräns som
#    inte rör sig med HALOGEN_HOST_RESERVE_GIB (testat: reserve 12 gav samma
#    16.00). Vision-pinnet är 0,84 GiB, så vi kräver golvet plus det.
#    Med --restart blir ett vägrat försök elve omstarter som tömmer burken.
#    Vi säger ifrån här i stället för att lämna den i det tillståndet.
NEEDED_MB=$(( 16 * 1024 + 900 ))   # 16.0 GiB golv + 0.84 GiB vision-pinn
AVAIL_MB=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)
if [ "${AVAIL_MB}" -lt "${NEEDED_MB}" ]; then
  echo "[STOPP] MemAvailable ${AVAIL_MB} MiB < golv ${NEEDED_MB} MiB (16.0 GiB + vision 0.84 GiB)."
  echo "        Servern skulle vägra pina och --restart skulle köra den i oändlig"
  echo "        omstart. Starta inte. Frigör RAM först, t.ex. genom att krympa"
  echo "        embedding-containern (se header) eller stoppa tunga processer."
  exit 1
fi
echo "[OK] Preflight: ${AVAIL_MB} MiB available >= ${NEEDED_MB} MiB golv."

# 5. Starta halogen på 8080.
docker run -d \
  --name halogen-flash-server \
  --restart unless-stopped \
  --device=/dev/dri \
  --device=/dev/kfd \
  --group-add video \
  --group-add $RENDER_GID \
  --security-opt seccomp=unconfined \
  --ipc=host \
  --ulimit memlock=-1:-1 \
  -p 8080:8080 \
  -v ${MODEL_DIR}:/models \
  -e HALOGEN_API_PORT=8080 \
  -e HALOGEN_DOWNLOAD=peonist-ai/halogen-qwen3.8-flash-next \
  -e HALOGEN_CHECKPOINT=/models/unsloth/Qwen3.8-Flash-Next-GGUF/UD-Q4_K_XL/Qwen3.8-Flash-Next-UD-Q4_K_XL-00001-of-00004.gguf \
  -e HALOGEN_CTX=262144 \
  -e HALOGEN_KV_POOL_POSITIONS=262144 \
  -e HALOGEN_KV_SLOTS=2 \
  -e HALOGEN_MAX_TOK=16384 \
  -e HALOGEN_HOST_RESERVE_GIB=16 \
  -e HALOGEN_VISION_TOWER=1 \
  -e HALOGEN_MODEL_ID=Qwen3.8-Flash-Next \
  ghcr.io/peonist-ai/halogen-flash-server:0.16.0

# 6. Embedding-modellen på 8081 ska ALDRIG skapas om när den redan är uppe —
#    Agent Zero (a0) är beroende av den. Körs bara om containern saknas.
if docker ps -aq -f "name=^llama-server-qwen-embed-vulkan$" | grep -q .; then
  docker start llama-server-qwen-embed-vulkan 2>/dev/null
  echo "[OK] Qwen3-Embedding-8B (8081) startad utan omstapelse."
else
  echo "[VARNING] llama-server-qwen-embed-vulkan finns inte — skapar den nu."
  echo "           ( Storleken är INTE godtyckligt: -c 8192/-b 4096/-ub 4096"
  echo "             är det som gör att vision-tornet får plats. Se header. )"
  docker run -d \
    --name llama-server-qwen-embed-vulkan \
    --restart unless-stopped \
    --no-healthcheck \
    --device=/dev/dri \
    --group-add video \
    --group-add $RENDER_GID \
    --cap-add=SYS_PTRACE \
    --security-opt seccomp=unconfined \
    --ipc=host \
    -p 8081:8081 \
    -v "${MODEL_DIR}:/models" \
    ghcr.io/ggml-org/llama.cpp:server-vulkan \
    -m /models/Qwen3-Embedding-8B-Q8_0.gguf \
    --host 0.0.0.0 \
    --port 8081 \
    -c 8192 \
    -np 1 \
    --cache-type-k q8_0 \
    --cache-type-v q8_0 \
    -ngl 999 \
    --threads 8 \
    --threads-batch 8 \
    --flash-attn on \
    --no-mmap \
    --embedding \
    -b 4096 \
    -ub 4096 \
    --pooling last \
    --alias "Qwen3-Embedding-8B"
fi

# 7. Diagnostik.
echo ""
echo "GTT före start (förhållandevis noll = ingen läckt GPU-minne):"
cat /sys/class/drm/card*/device/mem_info_gtt_used

echo ""
echo "[*] Första starten laddar ner 1,4 GiB draft-head + 0,8 GiB vision-torn och"
echo "    packar om 104 GiB GGUF i RAM (~18 s från kall disk, ~9 s varm)."
echo ""
echo "Följ uppstarten med:"
echo "  docker logs -f halogen-flash-server"
echo ""
echo "Läs efter dessa raderna i loggen:"
echo "  host memory left for everything else   -> ska vara >= 7,5 GiB (var ~7,8 med pool 262144)"
echo "  262144-position KV pool                 -> ska stå i startup-raden (7,2 GiB)"
echo "  checkpoint_format                      -> ska vara gguf"
echo "  vision tower ...                        -> ska stå utan fel"
echo "  WARNING .* no process holds the GPU    -> LEAKAD GTT, starta om burken"
echo "  engine listening                       -> redo"
echo ""
sleep 5
echo "--- /health ---"
curl -s --max-time 5 localhost:8080/health
echo ""
echo "--- /v1/models ---"
curl -s --max-time 5 localhost:8080/v1/models
echo ""
