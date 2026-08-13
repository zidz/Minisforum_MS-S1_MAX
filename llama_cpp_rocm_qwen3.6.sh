#!/bin/bash
MODEL_DIR="$(pwd)/models"
RENDER_GID=$(getent group render | cut -d: -f3)

echo "Startar llama.cpp-servern i Docker med ROCm/HIP-stöd..."

docker rm -f llama-server-qwen-first 2>/dev/null

docker run -d \
  --name llama-server-qwen-first \
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
  ghcr.io/ggml-org/llama.cpp:server-rocm \
  -m /models/Qwen3.6-27B-GGUF/Qwen3.6-27B-UD-Q8_K_XL.gguf \
  --host 0.0.0.0 \
  --port 8080 \
  -np 1 \
  -ngl 999 \
  -b 2048 \
  -ub 1024 \
  --cache-type-k q8_0 \
  --cache-type-v q8_0 \
  --threads 8 \
  --flash-attn on \
  --reasoning off \
  --reasoning-budget 0 \
  --chat-template-kwargs '{"enable_thinking": false}' \
  --jinja
