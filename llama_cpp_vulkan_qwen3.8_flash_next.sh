
  #--n-cpu-moe 999 \
  #-ngl 999 \
  #--load-mode mmap \
MODEL_DIR="$(pwd)/models"
RENDER_GID=$(getent group render | cut -d: -f3)

docker rm -f llama-server-qwen-first-vulkan 2>/dev/null
docker run -d \
  --name llama-server-qwen-first-vulkan \
  --restart unless-stopped \
  --device=/dev/dri \
  --device=/dev/kfd \
  --group-add video \
  --group-add $RENDER_GID \
  --cap-add=SYS_PTRACE \
  --security-opt seccomp=unconfined \
  --ipc=host \
  -e HIP_VISIBLE_DEVICES=0 \
  -e HSA_OVERRIDE_GFX_VERSION=11.5.0 \
  -e HSA_ENABLE_SDMA=0 \
  -p 8080:8080 \
  -v ${MODEL_DIR}:/models \
  ghcr.io/ggml-org/llama.cpp:server-vulkan \
  -m /models/unsloth/Qwen3.8-Flash-Next-GGUF/Q8_0/Qwen3.8-Flash-Next-Q8_0-00001-of-00006.gguf \
  -nr \
  --host 0.0.0.0 \
  --port 8080 \
  -np 1 \
  --flash-attn on \
  --cache-type-k q8_0 \
  --cache-type-v q8_0 \
  --jinja \
  --temp 1.0 \
  --top-p 0.95 \
  --top-k 20 \
  --min-p 0.00 \


echo "[✓] Qwen first LLM orkestrerad på port 8080."
echo "Servern startas i bakgrunden. Använd 'docker logs -f llama-server-qwen-first-vulkan' för att se laddningsprocessen."

