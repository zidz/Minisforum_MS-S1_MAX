#!/bin/bash

# Säkerställ att sökvägen till modellerna är absolut
MODEL_DIR="$(pwd)/models"

# Hämta det numeriska ID:t för render-gruppen på värdmaskinen
RENDER_GID=$(getent group render | cut -d: -f3)

echo "Startar llama.cpp-servern i Docker med Vulkan-stöd..."

docker run -d \
  --name llama-server-qwen-vulkan \
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
  -m /models/UD-Q4_K_XL/Qwen3.5-122B-A10B-UD-Q4_K_XL-00001-of-00003.gguf \
  --mmproj /models/mmproj-F16.gguf \
  --host 0.0.0.0 \
  --port 8080 \
  -c 131072 \
  --cache-type-k q8_0 \
  --cache-type-v q8_0 \
  -ngl 999 \
  --threads 16 \
  --threads-batch 16 \
  --flash-attn on \
  --fit off \
  --no-mmap \
  --jinja \
  --reasoning-format deepseek \
  --alias "Qwen3.5-122B-Coder"

docker run -d \
  --name qwen_embedding \
  --restart unless-stopped \
  --device=/dev/dri \
  --group-add video \
  --group-add $RENDER_GID \
  --cap-add=SYS_PTRACE \
  --security-opt seccomp=unconfined \
  --ipc=host \
  -p 8081:8080 \
  -v ${MODEL_DIR}:/models \
  ghcr.io/ggml-org/llama.cpp:server-vulkan \
  -m /models/Qwen3-Embedding-0.6B-f16.gguf \
  --host 0.0.0.0 \
  --port 8080 \
  --embedding \
  --pooling last \
  --n-gpu-layers 100

echo "Servern startas i bakgrunden. Använd 'docker logs -f llama-server-qwen-vulkan' för att se laddningsprocessen."
