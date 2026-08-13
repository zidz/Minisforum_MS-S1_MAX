
#--chat-template-kwargs '{"reasoning_effort":"max"}'
#--chat-template-kwargs '{"reasoning_effort":"high"}'
#--chat-template-kwargs '{"enable_thinking":false}'
#  -md /models/unsloth/DeepSeek-V4-Flash-0731-GGUF/dspark-DeepSeek-V4-Flash-0731-Q8_0.gguf \
#  --spec-type draft-dspark \
#  --spec-draft-n-max 3 \

# If device lost due to big context
# And maybe
# -b 2048 -ub 256

sudo sh -c 'echo 60000 > /sys/module/amdgpu/parameters/lockup_timeout'
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
  -m  /models/unsloth/DeepSeek-V4-Flash-0731-GGUF/UD-Q8_K_XL/DeepSeek-V4-Flash-0731-UD-Q8_K_XL-00001-of-00005.gguf  \
  -nr \
  --load-mode mmap \
  -fa on \
  --temp 1.0 \
  --top-p 1.0 \
  --min-p 0.01 \
  --n-cpu-moe 999 \
  -ngl 999 \
  --host 0.0.0.0 \
  --port 8080 \
  -np 1 \
  -c 150000 \
  --cache-type-k q8_0 \
  --cache-type-v q8_0 \
  --jinja
  #--temp 1.0 \
  #--top-p 0.95 \
  #--min-p 0.01 \

echo "[✓] Qwen first LLM orkestrerad på port 8080."
echo "Servern startas i bakgrunden. Använd 'docker logs -f llama-server-qwen-first-vulkan' för att se laddningsprocessen."

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
