#!/bin/bash

# Definiera mappen där modellerna ska sparas
MODEL_DIR="./models"
mkdir -p $MODEL_DIR

echo "Hämtar Qwen3.5-122B-A10B-UD-Q4_K_XL (splittade filer)..."
# Laddar ner alla GGUF-delar från den specifika undermappen
hf download unsloth/Qwen3.5-122B-A10B-GGUF \
  --include "UD-Q4_K_XL/*" \
  --local-dir $MODEL_DIR

echo "Hämtar mmproj-F16.gguf för multimodal vision-kapacitet..."
# Laddar ner projektionsfilen för bildhantering
hf download unsloth/Qwen3.5-122B-A10B-GGUF \
  --include "mmproj-F16.gguf" \
  --local-dir $MODEL_DIR

mkdir -p ${MODEL_DIR}/Qwen3.5-27B-GGUF

echo "Hämtar Qwen3.5-27B BF16(splittade filer)..."
# Laddar ner alla GGUF-delar från den specifika undermappen
hf download unsloth/Qwen3.5-27B-GGUF \
  --include "*BF16*" \
  --local-dir ${MODEL_DIR}/Qwen3.5-27B-GGUF

echo "Hämtar Qwen3.5-27B BF16(splittade filer)..."
# Laddar ner alla GGUF-delar från den specifika undermappen
hf download unsloth/Qwen3.5-27B-GGUF \
  --include "*mmproj*" \
  --local-dir ${MODEL_DIR}/Qwen3.5-27B-GGUF

hf download  Qwen/Qwen3-Embedding-0.6B-GGUF --include "Qwen3-Embedding-0.6B-f16.gguf" --local-dir $MODEL_DIR

echo "Nedladdning slutförd! Filerna finns i $MODEL_DIR"
