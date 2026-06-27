#!/bin/bash
# Säkerställ att sökvägen till modellerna är absolut
MODEL_DIR="$(pwd)/models"
# Dynamisk hämtning av det numeriska ID:t för render-gruppen för Vulkan IPC
RENDER_GID=$(getent group render | cut -d: -f3)
echo "Startar llama.cpp-servern i Docker med Vulkan-stöd..."

# ──────────────────────────────────────────────
# Server 1: Qwen3.6-27B (Chat)
# ──────────────────────────────────────────────
docker rm -f llama-server-qwen-chat-vulkan 2>/dev/null
docker run -d \
  --name llama-server-qwen-chat-vulkan \
  --restart unless-stopped \
  --device=/dev/dri \
  --device=/dev/kfd \                    # ← NY: AMD compute-enhet
  --group-add video \                    # ← Behålls: Vulkan-access
  --group-add $RENDER_GID \              # ← Behålls: Vulkan-access
  --cap-add=SYS_PTRACE \                 # ← Behålls: Debugging
  --security-opt seccomp=unconfined \    # ← Behålls: ROCm/Vulkan kräver flexibilitet
  --ipc=host \                           # ← Behålls: Delat minne för prestanda
  --memory=120g \                        # ← NY: Förhindra OOM-kill
  --memory-swap=120g \                   # ← NY: Inaktivera swap
  -e HIP_VISIBLE_DEVICES=0 \            # ← NY: GPU-identifiering
  -e HSA_OVERRIDE_GFX_VERSION=11.5.0 \  # ← NY: Strix Halo-genkänning
  -e HSA_ENABLE_SDMA=0 \                # ← NY: Stabilitet
  -p 8080:8080 \
  -v ${MODEL_DIR}:/models \
  ghcr.io/ggml-org/llama.cpp:server-vulkan \
  -m /models/Qwen3.6-27B-GGUF/Qwen3.6-27B-UD-Q4_K_XL.gguf \
  --mmproj /models/Qwen3.6-27B-GGUF/mmproj-BF16.gguf \
  --host 0.0.0.0 \
  --port 8080 \
  -c 262144 \                           # 256K context
  -np 1 \                               # Prefetch threads
  -ngl 999 \                            # Alla lager till GPU ✅
  --threads 24 \                        # ← ÄNDRA: Från 16 till 24
  --threads-batch 24 \                  # ← ÄNDRA: Från 16 till 24
  --cache-type-k q8_0 \                 # Hög precision KV-cache ✅
  --cache-type-v q8_0 \                 # Hög precision KV-cache ✅
  --flash-attn on \                     # Snabbare attention ✅
  --temperature 0.6 \
  --top-p 0.95 \
  --top-k 20 \
  --min-p 0.00 \
  --presence-penalty 0.0 \
  --repeat_penalty 1.0 \
  --fit off \                           # Ingen fit-modus ✅
  --jinja \                             # Jinja-chatmallar ✅
  --alias "Qwen3.6-27B"

echo "[✓] Chat-server orkestrerad på port 8080. Använd 'docker logs -f llama-server-qwen-chat-vulkan' för att se laddningsprocessen."

# ──────────────────────────────────────────────
# Server 2: Qwen3-Embedding-8B (Embeddings)
# ──────────────────────────────────────────────
docker rm -f llama-server-qwen-embed-vulkan 2>/dev/null
docker run -d \
  --name llama-server-qwen-embed-vulkan \
  --restart unless-stopped \
  --device=/dev/dri \
  --device=/dev/kfd \                    # ← NY: AMD compute-enhet
  --group-add video \                    # ← Behålls: Vulkan-access
  --group-add $RENDER_GID \              # ← Behålls: Vulkan-access
  --cap-add=SYS_PTRACE \                 # ← Behålls: Debugging
  --security-opt seccomp=unconfined \    # ← Behålls: ROCm/Vulkan kräver flexibilitet
  --ipc=host \                           # ← Behålls: Delat minne för prestanda
  --memory=120g \                        # ← NY: Förhindra OOM-kill
  --memory-swap=120g \                   # ← NY: Inaktivera swap
  -e HIP_VISIBLE_DEVICES=0 \            # ← NY: GPU-identifiering
  -e HSA_OVERRIDE_GFX_VERSION=11.5.0 \  # ← NY: Strix Halo-genkänning
  -e HSA_ENABLE_SDMA=0 \                # ← NY: Stabilitet
  -p 8081:8081 \
  -v "${MODEL_DIR}:/models" \
  ghcr.io/ggml-org/llama.cpp:server-vulkan \
  -m /models/Qwen3-Embedding-8B-Q8_0.gguf \
  --host 0.0.0.0 \
  --port 8081 \
  -c 32768 \                            # 32K context
  -np 1 \                               # Prefetch threads
  --cache-type-k q8_0 \                 # Hög precision KV-cache ✅
  --cache-type-v q8_0 \                 # Hög precision KV-cache ✅
  -ngl 999 \                            # Alla lager till GPU ✅
  --threads 12 \                        # ← ÄNDRA: Från 8 till 12
  --threads-batch 12 \                  # ← ÄNDRA: Från 8 till 12
  --flash-attn on \                     # Snabbare attention ✅
  --no-mmap \                           # Behålls: Undvik mmap-problem ✅
  --embedding \                          # Embedding-läge ✅
  -b 8192 \                             # Batch-storlek
  -ub 8192 \                            # Ungrouped batch
  --pooling last \                      # Last-token pooling ✅
  --alias "Qwen3-Embedding-8B"

echo "[✓] Inbäddningsserver orkestrerad på port 8081."

# ──────────────────────────────────────────────
# Server 3: Qwen3.6-35B-A3B (Chat)
# ──────────────────────────────────────────────
docker rm -f llama-server-qwen-9b-vulkan 2>/dev/null
docker run -d \
  --name llama-server-qwen-9b-vulkan \
  --restart unless-stopped \
  --device=/dev/dri \
  --device=/dev/kfd \                    # ← NY: AMD compute-enhet
  --group-add video \                    # ← Behålls: Vulkan-access
  --group-add $RENDER_GID \              # ← Behålls: Vulkan-access
  --cap-add=SYS_PTRACE \                 # ← Behålls: Debugging
  --security-opt seccomp=unconfined \    # ← Behålls: ROCm/Vulkan kräver flexibilitet
  --ipc=host \                           # ← Behålls: Delat minne för prestanda
  --memory=120g \                        # ← NY: Förhindra OOM-kill
  --memory-swap=120g \                   # ← NY: Inaktivera swap
  -e HIP_VISIBLE_DEVICES=0 \            # ← NY: GPU-identifiering
  -e HSA_OVERRIDE_GFX_VERSION=11.5.0 \  # ← NY: Strix Halo-genkänning
  -e HSA_ENABLE_SDMA=0 \                # ← NY: Stabilitet
  -p 8082:8082 \
  -v "${MODEL_DIR}:/models" \
  ghcr.io/ggml-org/llama.cpp:server-vulkan \
  -m /models/unsloth/Qwen3.6-35B-A3B-GGUF/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf \
  --mmproj /models/unsloth/Qwen3.6-35B-A3B-GGUF/mmproj-BF16.gguf \
  --host 0.0.0.0 \
  --port 8082 \
  -c 262144 \                           # 256K context
  -np 1 \                               # Prefetch threads
  --cache-type-k q8_0 \                 # Hög precision KV-cache ✅
  --cache-type-v q8_0 \                 # Hög precision KV-cache ✅
  -ngl 999 \                            # Alla lager till GPU ✅
  --threads 8 \                         # ← ÄNDRA: Från 4 till 8
  --threads-batch 8 \                   # ← ÄNDRA: Från 4 till 8
  --flash-attn on \                     # Snabbare attention ✅
  --alias "Qwen3.6-35B-A3B"

echo "[✓] Chat-9b-server orkestrerad på port 8082."
