#!/bin/zsh

set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
model_root="${EVA_MODEL_ROOT:-${project_dir}/.eva-models/huggingface}"
language_model_name="Qwen3.5-2B-MLX-4bit"
language_repo="mlx-community/Qwen3.5-2B-MLX-4bit"
language_revision="93760be4f1f69842a46bc13dbdc0f19e291392a3"
language_dir="${model_root}/mlx-community/${language_model_name}"
speech_repo="mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-4bit"
speech_revision="08c72cad5e2fd0f41730c8bd1f28149585e46361"
speech_tokenizer_repo="AtomGradient/Qwen3-TTS-0.6B-CustomVoice-4bit-pruned-vocab-lite"
speech_tokenizer_revision="863a1dfc07aae0fc11c40507ba1b5aa408abc808"
speech_dir="${model_root}/mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-4bit"

download_file() {
  local repo="$1"
  local revision="$2"
  local relative_path="$3"
  local destination_root="$4"
  local destination="${destination_root}/${relative_path}"

  /bin/mkdir -p "$(/usr/bin/dirname "${destination}")"
  if [[ -s "${destination}" ]]; then
    return
  fi

  /usr/bin/curl \
    --location \
    --fail \
    --retry 5 \
    --retry-delay 2 \
    --show-error \
    --progress-bar \
    "https://huggingface.co/${repo}/resolve/${revision}/${relative_path}?download=true" \
    --output "${destination}.partial"
  /bin/mv "${destination}.partial" "${destination}"
}

/bin/mkdir -p "${language_dir}" "${speech_dir}"

for file in \
  README.md \
  chat_template.jinja \
  config.json \
  model.safetensors \
  model.safetensors.index.json \
  preprocessor_config.json \
  processor_config.json \
  tokenizer.json \
  tokenizer_config.json \
  video_preprocessor_config.json \
  vocab.json
do
  download_file "${language_repo}" "${language_revision}" "${file}" "${language_dir}"
done

for file in \
  README.md \
  config.json \
  generation_config.json \
  merges.txt \
  model.safetensors \
  model.safetensors.index.json \
  preprocessor_config.json \
  speech_tokenizer/config.json \
  speech_tokenizer/configuration.json \
  speech_tokenizer/model.safetensors \
  tokenizer_config.json \
  vocab.json
do
  download_file "${speech_repo}" "${speech_revision}" "${file}" "${speech_dir}"
done

# The MLX conversion currently omits tokenizer.json. Its vocabulary, merges and
# tokenizer configuration are byte-identical to the compatible Swift conversion,
# so we source only this tokenizer artifact there; all neural weights remain the
# standard mlx-community model.
download_file \
  "${speech_tokenizer_repo}" \
  "${speech_tokenizer_revision}" \
  "tokenizer.json" \
  "${speech_dir}"

[[ -s "${language_dir}/config.json" && -s "${language_dir}/model.safetensors" ]]
[[ -s "${speech_dir}/config.json" && -s "${speech_dir}/model.safetensors" ]]
[[ -s "${speech_dir}/speech_tokenizer/model.safetensors" ]]

/bin/mkdir -p "${project_dir}/Resources/Models"
/bin/ln -sfn "${language_dir}" "${project_dir}/Resources/Models/${language_model_name}"
/bin/ln -sfn "${speech_dir}" "${project_dir}/Resources/Models/Qwen3-TTS-12Hz-0.6B-CustomVoice-4bit"

/usr/bin/du -sh "${language_dir}" "${speech_dir}"
