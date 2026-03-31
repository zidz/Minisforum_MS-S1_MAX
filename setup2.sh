#!/bin/bash

# Definition av absolut sökväg för modellagring för att underlätta Docker-montering
MODEL_DIR="$(pwd)/models"
mkdir -p "$MODEL_DIR"

#echo "Initierar höghastighetsnedladdning med hf_transfer (kräver python-biblioteket hf_transfer)..."
#export HF_HUB_ENABLE_HF_TRANSFER=1

echo "[1/3] Hämtar Qwen3.5-122B-A10B-UD-Q4_K_XL (splittade filarkiv) från Unsloth..."
hf download unsloth/Qwen3.5-122B-A10B-GGUF \
  --include "UD-Q4_K_XL/*" \
  --local-dir "$MODEL_DIR/UD-Q4_K_XL"

echo "[2/3] Hämtar mmproj-F16.gguf för att aktivera multimodal maskinseende..."
hf download unsloth/Qwen3.5-122B-A10B-GGUF \
  --include "mmproj-F16.gguf" \
  --local-dir "$MODEL_DIR"

echo "[3/3] Hämtar Qwen3-Embedding-8B (Q8_0) för semantisk vektorisering och RAG..."
hf download Qwen/Qwen3-Embedding-8B-GGUF \
  --include "Qwen3-Embedding-8B-Q8_0.gguf" \
  --local-dir "$MODEL_DIR"

echo "Systemnedladdning slutförd! Modellfilerna är nu tillgängliga i $MODEL_DIR."
