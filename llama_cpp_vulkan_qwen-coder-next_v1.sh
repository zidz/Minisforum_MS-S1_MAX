#!/bin/bash

# Deklarera absolut filsökväg till modellerna
MODEL_DIR="$(pwd)/models"

# Dynamisk hämtning av det numeriska ID:t för render-gruppen för Vulkan IPC
RENDER_GID=$(getent group render | cut -d: -f3)

echo "Driftsätter LLM-infrastruktur på AMD Strix Halo via Vulkan RADV..."

# ----------------------------------------------------------------------
# INSTANS 1: Kärnintelligens (Qwen3.5 122B Chat & Kodgenerering) - Port 8080
# ----------------------------------------------------------------------
docker rm -f llama-server-qwen-chat-vulkan 2>/dev/null

docker run -d \
  --name llama-server-qwen-chat-vulkan \
  --restart unless-stopped \
  --device=/dev/dri \
  --group-add video \
  --group-add $RENDER_GID \
  --cap-add=SYS_PTRACE \
  --security-opt seccomp=unconfined \
  --ipc=host \
  -p 8080:8080 \
  -v "${MODEL_DIR}:/models" \
  ghcr.io/ggml-org/llama.cpp:server-vulkan \
  -m /models/UD-Q4_K_XL/Qwen3-Coder-Next-UD-Q4_K_XL.gguf \
  --host 0.0.0.0 \
  --port 8080 \
  -c 262144 \
  --cache-type-k q4_0 \
  --cache-type-v q4_0 \
  -ngl 999 \
  --threads 16 \
  --threads-batch 16 \
  --kv-unified \
  --flash-attn on \
  --no-mmap \
  --jinja \
  --parallel 1 \
  --temp 1.0 --top-p 0.95 --min-p 0.01 --top-k 40 \
  --no-context-shift \
  --alias "qwen3-coder"
  #--reasoning-format deepseek \

#FROM https://unsloth.ai/docs/basics/claude-code
#    --model unsloth/Qwen3.5-35B-A3B-GGUF/Qwen3.5-35B-A3B-UD-Q4_K_XL.gguf \
#    --alias "unsloth/Qwen3.5-35B-A3B" \
#    --temp 0.6 \
#    --top-p 0.95 \
#    --top-k 20 \
#    --min-p 0.00 \
#    --port 8001 \
#    --kv-unified \
#    --cache-type-k q8_0 --cache-type-v q8_0 \
#    --flash-attn on --fit on \
#    --ctx-size 131072 # change as required

echo "[✓] Chat-server orkestrerad på port 8080 med 131 072 tokens kontext."

# ----------------------------------------------------------------------
# INSTANS 2: RAG-motor (Qwen3 Embedding 8B Semantisk Sökning) - Port 8081
# ----------------------------------------------------------------------
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

echo "[✓] Inbäddnings-server orkestrerad på port 8081."
docker rm -f llama-server-qwen-web-vulkan 2>/dev/null
docker run -d \
  --name llama-server-qwen-web-vulkan \
  --restart unless-stopped \
  --device=/dev/dri \
  --group-add video \
  --group-add $RENDER_GID \
  --cap-add=SYS_PTRACE \
  --security-opt seccomp=unconfined \
  --ipc=host \
  -p 8082:8082 \
  -v "${MODEL_DIR}:/models" \
  ghcr.io/ggml-org/llama.cpp:server-vulkan \
  -m /models/Qwen3.5-WebAgent/Qwen3.5-9B-UD-Q4_K_XL.gguf \
  --mmproj /models/Qwen3.5-WebAgent/mmproj-F16.gguf \
  --host 0.0.0.0 \
  --port 8082 \
  -c 32768 \
  --cache-type-k q4_0 \
  --cache-type-v q4_0 \
  -ngl 999 \
  --threads 16 \
  --threads-batch 16 \
  --flash-attn on \
  --no-mmap \
  --alias "qwen3.5-web"

  
echo "Observera initieringssekvenserna med kommandot: docker logs -f llama-server-qwen-chat-vulkan"
