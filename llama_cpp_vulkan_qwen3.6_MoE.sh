#!/bin/bash
# Säkerställ att sökvägen till modellerna är absolut
MODEL_DIR="$(pwd)/models"
# Dynamisk hämtning av det numeriska ID:t för render-gruppen för Vulkan IPC
RENDER_GID=$(getent group render | cut -d: -f3)
#  --chat-template-kwargs '{"enable_thinking":false}' \
#  -c 262144 \
#  --reasoning-budget -1 \
#  --restart unless-stopped \
#  --fit off \
#  --chat-template-kwargs '{"preserve_thinking": true}' \
echo "Startar llama.cpp-servern i Docker med Vulkan-stöd..."

docker rm -f llama-server-qwen-first-vulkan 2>/dev/null
#docker run -d \
#  --name llama-server-qwen-first-vulkan \
#  --device=/dev/dri \
#  --device=/dev/kfd \
#  --group-add video \
#  --group-add $RENDER_GID \
#  --cap-add=SYS_PTRACE \
#  --security-opt seccomp=unconfined \
#  --ipc=host \
#  -e HIP_VISIBLE_DEVICES=0 \
#  -e HSA_OVERRIDE_GFX_VERSION=11.5.0 \
#  -e HSA_ENABLE_SDMA=0 \
#  -p 8080:8080 \
#  -v ${MODEL_DIR}:/models \
#  ghcr.io/ggml-org/llama.cpp:server-vulkan \
#  -m /models/Qwen3.6-27B-GGUF/Qwen3.6-27B-UD-Q8_K_XL.gguf \
#  --mmproj /models/Qwen3.6-27B-GGUF/mmproj-BF16.gguf \
#  --no-mmap \
##  --host 0.0.0.0 \
#  --port 8080 \
#  -c 262144 \
#  -np 1 \
#  -ngl 999 \
#  --cache-type-k q8_0 \
#  --cache-type-v q8_0 \
#  --threads 8 \
#  --threads-batch 8 \
#  --flash-attn on \
#  --reasoning off \
#  --reasoning-budget 0 \
#  --chat-template-kwargs '{"enable_thinking": false}' \
#  --jinja
#echo "[✓] Qwen first LLM orkestrerad på port 8080."
#echo "Servern startas i bakgrunden. Använd 'docker logs -f llama-server-qwen-first-vulkan' för att se laddningsprocessen."

docker rm -f llama-server-qwen-embed-vulkan 2>/dev/null

docker run -d \
  --name llama-server-qwen-embed-vulkan \
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
  -m /models/Qwen3-Embedding-8B-Q8_0.gguf \
  --host 0.0.0.0 \
  --port 8081 \
  -c 32768 \
  -np 1 \
  -ngl 999 \
  --threads 8 \
  --threads-batch 8 \
  --flash-attn on \
  --no-mmap \
  --embedding \
  -b 8192 \
  -ub 8192 \
  --pooling last

echo "[✓] Inbäddnings-server orkestrerad på port 8081."
echo "Servern startas i bakgrunden. Använd 'docker logs -f llama-server-qwen-embed-vulkan' för att se laddningsprocessen."
docker rm -f llama-server-qwen-second-vulkan 2>/dev/null
docker run -d \
  --name llama-server-qwen-second-vulkan \
  --restart unless-stopped \
  --device=/dev/dri \
  --group-add video \
  --device=/dev/kfd \
  --group-add $RENDER_GID \
  --cap-add=SYS_PTRACE \
  --security-opt seccomp=unconfined \
  --ipc=host \
  -e HIP_VISIBLE_DEVICES=0 \
  -e HSA_OVERRIDE_GFX_VERSION=11.5.0 \
  -e HSA_ENABLE_SDMA=0 \
  -p 8080:8080 \
  -v "${MODEL_DIR}:/models" \
  ghcr.io/ggml-org/llama.cpp:server-vulkan \
  -m /models/unsloth/Qwen3.6-35B-A3B-GGUF/Qwen3.6-35B-A3B-UD-Q8_K_XL.gguf \
  --mmproj /models/unsloth/Qwen3.6-35B-A3B-GGUF/mmproj-BF16.gguf \
  --no-mmap \
  --host 0.0.0.0 \
  --port 8080 \
  -c 128000 \
  -np 1 \
  -ngl 999 \
  --cache-type-k q8_0 \
  --cache-type-v q8_0 \
  --threads 8 \
  --threads-batch 8 \
  --flash-attn on \
  --reasoning off \
  --reasoning-budget 0 \
  --jinja
echo "[✓] Qwen second LLM orkestrerad på port 8082."
echo "Servern startas i bakgrunden. Använd 'docker logs -f llama-server-qwen-second-vulkan' för att se laddningsprocessen."
