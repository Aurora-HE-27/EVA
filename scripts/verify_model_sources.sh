#!/bin/zsh

set -euo pipefail

language_repo="mlx-community/Qwen3.5-2B-MLX-4bit"
language_revision="93760be4f1f69842a46bc13dbdc0f19e291392a3"
speech_repo="mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-4bit"
speech_revision="08c72cad5e2fd0f41730c8bd1f28149585e46361"
tokenizer_repo="AtomGradient/Qwen3-TTS-0.6B-CustomVoice-4bit-pruned-vocab-lite"
tokenizer_revision="863a1dfc07aae0fc11c40507ba1b5aa408abc808"

verify_file() {
  local repo="$1"
  local revision="$2"
  local relative_path="$3"
  /usr/bin/curl \
    --location \
    --fail \
    --silent \
    --show-error \
    --range 0-0 \
    --output /dev/null \
    "https://huggingface.co/${repo}/resolve/${revision}/${relative_path}"
}

verify_file "$language_repo" "$language_revision" "config.json"
verify_file "$language_repo" "$language_revision" "model.safetensors"
verify_file "$speech_repo" "$speech_revision" "config.json"
verify_file "$speech_repo" "$speech_revision" "model.safetensors"
verify_file "$speech_repo" "$speech_revision" "speech_tokenizer/model.safetensors"
verify_file "$tokenizer_repo" "$tokenizer_revision" "tokenizer.json"

echo "公开模型源及固定版本均可访问。"
