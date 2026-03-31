#!/bin/bash

# Säkerställ att sökvägen till modellerna är absolut
MODEL_DIR="$(pwd)/models"

echo "Startar llama.cpp-servern i Docker med Vulkan-stöd..."

docker run -d \
  --name llama-server-qwen-vulkan \
  --restart unless-stopped \
  --device=/dev/dri \
  --group-add video \
  --group-add render \
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
  --temperature 0.3 \
  --top-p 0.95 \
  --top-k 20 \
  --min-p 0.01 \
  --repeat-penalty 1.3 \
  --flash-attn on \
  --fit off \
  --no-mmap \
  --jinja \
  --reasoning-format deepseek \
  --alias "Qwen3.5-122B-Coder"

echo "Servern startas i bakgrunden. Använd 'docker logs -f llama-server-qwen-vulkan' för att se laddningsprocessen."
