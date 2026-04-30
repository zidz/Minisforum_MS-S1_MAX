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

hf download unsloth/Qwen3.5-27B-GGUF \
  --include "mmproj-BF16.gguf" \
  --local-dir ${MODEL_DIR}/Qwen3.5-27B-GGUF

hf download unsloth/Qwen3.5-2B-GGUF \
  --include "Qwen3.5-2B-UD-Q6_K_XL.gguf" \
  --local-dir ${MODEL_DIR}/Qwen3.5-2B-GGUF

echo "Hämtar Qwen3.5-27B Q6"
hf download unsloth/Qwen3.5-27B-GGUF \
  --include "Qwen3.5-27B-UD-Q6_K_XL.gguf" \
  --local-dir ${MODEL_DIR}/Qwen3.5-27B-GGUF

echo "Hämtar Qwen3.6-27B UD Q8"
hf download unsloth/Qwen3.6-27B-GGUF \
  --include "unsloth/Qwen3.6-27B-UD-Q8_K_XL.gguf" \
  --local-dir ${MODEL_DIR}/Qwen3.6-27B-GGUF

echo "Hämtar Qwen3.6-27B UD Q4"
hf download unsloth/Qwen3.6-27B-GGUF \
  --include "*Qwen3.6-27B-UD-Q4_K_XL*" \
  --local-dir ${MODEL_DIR}/Qwen3.6-27B-GGUF

hf download unsloth/Qwen3.6-27B-GGUF \
  --include "mmproj-BF16.gguf" \
  --local-dir ${MODEL_DIR}/Qwen3.6-27B-GGUF

mkdir -p ${MODEL_DIR}/bartowski/Qwen3.5-27B-GGUF

hf download bartowski/Qwen_Qwen3.5-27B-GGUF \
  --include "mmproj-Qwen_Qwen3.5-27B-bf16.gguf" \
  --local-dir ${MODEL_DIR}/bartowski/Qwen3.5-27B-GGUF

hf download bartowski/Qwen_Qwen3.5-2B-GGUF \
  --include "Qwen_Qwen3.5-2B-Q6_K_L.gguf" \
  --local-dir ${MODEL_DIR}/bartowski/Qwen3.5-2B-GGUF

mkdir -p ${MODEL_DIR}/unsloth/Qwen3.6-35B-A3B-GGUF

hf download unsloth/Qwen3.6-35B-A3B-GGUF \
  --include "Qwen3.6-35B-A3B-UD-Q6_K_XL.gguf" \
  --local-dir ${MODEL_DIR}/unsloth/Qwen3.6-35B-A3B-GGUF

hf download unsloth/Qwen3.6-35B-A3B-GGUF \
  --include "Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf" \
  --local-dir ${MODEL_DIR}/unsloth/Qwen3.6-35B-A3B-GGUF

hf download unsloth/Qwen3.6-35B-A3B-GGUF \
  --include "mmproj-BF16.gguf" \
  --local-dir ${MODEL_DIR}/unsloth/Qwen3.6-35B-A3B-GGUF

hf download  Qwen/Qwen3-Embedding-0.6B-GGUF --include "Qwen3-Embedding-0.6B-f16.gguf" --local-dir $MODEL_DIR

echo "Nedladdning slutförd! Filerna finns i $MODEL_DIR"
