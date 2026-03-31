#!/bin/bash

# Definition av absolut sökväg för modellagring för att underlätta Docker-montering
MODEL_DIR="$(pwd)/models"
mkdir -p "$MODEL_DIR"

echo "[1/3] Hämtar Qwen3-Coder-Next (UD-Q4_K_XL splittade filarkiv) från Unsloth..."
hf download unsloth/Qwen3-Coder-Next-GGUF \
  --include "*UD-Q4_K_XL*" \
  --local-dir "$MODEL_DIR/UD-Q4_K_XL"

echo "[2/3] Hämtar en mindre Qwen3.5 (9B Q4_K_XL) för Agent Zero webbsökning..."
hf download unsloth/Qwen3.5-9B-GGUF \
    --local-dir unsloth/Qwen3.5-9B-GGUF \
    --include "*mmproj-F16*" \
    --include "*UD-Q4_K_XL*" \
    --local-dir "$MODEL_DIR/Qwen3.5-WebAgent"

echo "[3/3] Hämtar Qwen3-Embedding-8B (Q8_0) för semantisk vektorisering och RAG..."
hf download Qwen/Qwen3-Embedding-8B-GGUF \
  --include "Qwen3-Embedding-8B-Q8_0.gguf" \
  --local-dir "$MODEL_DIR/Embeddings"

echo "Systemnedladdning slutförd! Modellfilerna är nu tillgängliga i $MODEL_DIR."
