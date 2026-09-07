#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
model_dir="${project_dir}/.eva-models/huggingface/openbmb/MiniCPM-o-4_5-gguf"
repository="openbmb/MiniCPM-o-4_5-gguf"
revision="db25077c33951fe163b42986fba0132e279872a2"
base_url="https://huggingface.co/${repository}/resolve/${revision}"

files=(
  "MiniCPM-o-4_5-Q4_K_M.gguf"
  "audio/MiniCPM-o-4_5-audio-F16.gguf"
  "vision/MiniCPM-o-4_5-vision-F16.gguf"
  "tts/MiniCPM-o-4_5-projector-F16.gguf"
  "tts/MiniCPM-o-4_5-tts-F16.gguf"
  "token2wav-gguf/encoder.gguf"
  "token2wav-gguf/flow_extra.gguf"
  "token2wav-gguf/flow_matching.gguf"
  "token2wav-gguf/hifigan2.gguf"
  "token2wav-gguf/prompt_cache.gguf"
)

for relative_path in "${files[@]}"; do
  destination="${model_dir}/${relative_path}"
  mkdir -p "${destination:h}"
  echo "Downloading ${relative_path}"
  curl --fail --location --continue-at - --retry 5 \
    --output "${destination}" "${base_url}/${relative_path}?download=true"
done

echo "Verifying pinned Hugging Face LFS SHA-256 hashes..."
(cd "${model_dir}" && shasum -a 256 -c "${project_dir}/Research/NativeSpeech/SHA256SUMS")

echo "Native speech model set ready: ${model_dir}"
