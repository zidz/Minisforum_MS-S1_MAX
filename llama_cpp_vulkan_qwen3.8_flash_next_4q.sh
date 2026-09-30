#!/bin/bash
#  --chat-template-kwargs '{"preserve_thinking":true,"reasoning_effort":"medium"}'
#  --chat-template-kwargs '{"preserve_thinking":true,"reasoning_effort":"xhigh"}'
#  --mmproj /models/unsloth/Qwen3.8-27B-GGUF/mmproj-BF16.gguf \
#  --spec-default \
#  --spec-type draft-mtp \
#  --spec-draft-n-max 3 \


# Säkerställ att sökvägen till modellerna är absolut
#  --threads 8 \
#  --threads-batch 8 \
MODEL_DIR="$(pwd)/models"
# Dynamisk hämtning av det numeriska ID:t för render-gruppen för Vulkan IPC
RENDER_GID=$(getent group render | cut -d: -f3)
echo "Startar llama.cpp-servern i Docker med Vulkan-stöd..."

docker rm -f llama-server-qwen-first-vulkan 2>/dev/null
docker run -d \
  --name llama-server-qwen-first-vulkan \
  --restart unless-stopped \
  --device=/dev/dri \
  --group-add video \
  --group-add $RENDER_GID \
  --cap-add=SYS_PTRACE \
  --security-opt seccomp=unconfined \
  --ipc=host \
  -p 8080:8080 \
  -v ${MODEL_DIR}:/models \
  ghcr.io/ggml-org/llama.cpp:server-vulkan \
  -m /models/unsloth/Qwen3.8-Flash-Next-GGUF/UD-Q4_K_XL/Qwen3.8-Flash-Next-UD-Q4_K_XL-00001-of-00004.gguf \
  --host 0.0.0.0 \
  --port 8080 \
  --reasoning-preserve \
  --cache-type-k q4_0 \
  --cache-type-v q4_0 \
  -c 128000 \
  -np 1 \
  --cache-ram -1 \
  --cache-idle-slots \
  -ngl 999 \
  --flash-attn on \
  --temperature 1.0 \
  --top-p 0.95 \
  --top-k 20 \
  --min-p 0.0 \
  --presence-penalty 0.0 \
  --repeat_penalty 1.0 \
  --fit off \
  --jinja 

echo "Servern startas i bakgrunden. Använd 'docker logs -f llama-server-qwen-chat-vulkan' för att se laddningsprocessen."
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
  --cache-type-k q8_0 \
  --cache-type-v q8_0 \
  -ngl 999 \
  --threads 8 \
  --threads-batch 8 \
  --flash-attn on \
  --no-mmap \
  --embedding \
  -b 8192 \
  -ub 8192 \
  --pooling last \
  --alias "Qwen3-Embedding-8B"

