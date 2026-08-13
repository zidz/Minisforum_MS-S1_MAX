
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
  -m /models/unsloth/GLM-5.2-GGUF/UD-Q5_K_XL/GLM-5.2-UD-Q5_K_XL-00001-of-00013.gguf \
  -nr \
  --mmap \
  --n-cpu-moe 999 \
  -ngl 999 \
  --host 0.0.0.0 \
  --port 8080 \
  -np 1 \
  -c 32768 \
  --cache-type-k q8_0 \
  --cache-type-v q8_0 \
  --jinja
  #--temp 1.0 \
  #--top-p 0.95 \
  #--min-p 0.01 \

echo "[✓] Qwen first LLM orkestrerad på port 8080."
echo "Servern startas i bakgrunden. Använd 'docker logs -f llama-server-qwen-first-vulkan' för att se laddningsprocessen."

