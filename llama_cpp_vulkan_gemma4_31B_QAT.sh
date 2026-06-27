#!/bin/bash
# Säkerställ att sökvägen till modellerna är absolut
MODEL_DIR="$(pwd)/models"
# Dynamisk hämtning av det numeriska ID:t för render-gruppen för Vulkan IPC
RENDER_GID=$(getent group render | cut -d: -f3)
#  --chat-template-kwargs '{"enable_thinking":false}' \
#  -c 262144 \
#  --reasoning-budget -1 \
#  -b 2048 \
#  -ub 2048 \
docker rm -f llama-server-embed-vulkan 2>/dev/null

docker run -d \
  --name llama-server-embed-vulkan \
  --restart unless-stopped \
  --device=/dev/dri \
  --group-add video \
  --group-add $RENDER_GID \
  --cap-add=SYS_PTRACE \
  --security-opt seccomp=unconfined \
  --ipc=host \
  -p 8081:8081 \
  -v "${MODEL_DIR}:/models" \
  ghcr.io/ggml-org/llama.cpp:server-vulkan \
  -m /models/unsloth/embeddinggemma-300m-GGUF/embeddinggemma-300M-Q8_0.gguf \
  --host 0.0.0.0 \
  --port 8081 \
  -np 1 \
  -ngl 999 \
  --flash-attn on \
  --no-mmap \
  --embedding

echo "[✓] Inbäddnings-server orkestrerad på port 8081."
echo "Servern startas i bakgrunden. Använd 'docker logs -f llama-server-embed-vulkan' för att se laddningsprocessen."
docker rm -f llama-server-second 2>/dev/null
docker run -d \
  --name llama-server-second \
  --restart unless-stopped \
  --device=/dev/dri \
  --group-add video \
  --device=/dev/kfd \
  --group-add $RENDER_GID \
  --cap-add=SYS_PTRACE \
  --security-opt seccomp=unconfined \
  --ipc=host \
  -p 8080:8080 \
  -v "${MODEL_DIR}:/models" \
  ghcr.io/ggml-org/llama.cpp:server-vulkan \
  -m /models/unsloth/gemma-4-31B-it-qat-GGUF/gemma-4-31B-it-qat-UD-Q4_K_XL.gguf \
  --mmproj /models/unsloth/gemma-4-31B-it-qat-GGUF/mmproj-BF16.gguf \
  --host 0.0.0.0 \
  --port 8080 \
  -c 65576 \
  -b 1024 \
  -ub 1024 \
  -np 1 \
  --temp 1.0 \
  --top-p 0.95 \
  --top-k 64 \
  -ngl 999 \
  --no-mmap \
  --embedding \
  --flash-attn off \

echo "Servern startas i bakgrunden. Använd 'docker logs -f llama-server-second' för att se laddningsprocessen."
