#!/bin/zsh
set -euo pipefail
unsetopt BG_NICE
zmodload zsh/datetime

project_dir="${0:A:h:h}"
runtime_dir="${project_dir}/.eva-runtime/llama.cpp-omni"
model_dir="${project_dir}/.eva-models/huggingface/openbmb/MiniCPM-o-4_5-gguf"
output_dir="${project_dir}/Artifacts/NativeSpeech"
server_bin="${runtime_dir}/build/bin/llama-omni-server"
model_file="${model_dir}/MiniCPM-o-4_5-Q4_K_M.gguf"
reference_audio="${runtime_dir}/tools/omni/assets/default_ref_audio/default_ref_audio.wav"
port="${EVA_NATIVE_SPEECH_PORT:-19080}"

[[ -x "${server_bin}" ]] || {
  echo "Runtime missing. Run ./scripts/setup_native_speech_lab.sh first." >&2
  exit 1
}
[[ -f "${model_file}" ]] || {
  echo "Models missing. Run ./scripts/download_native_speech_models.sh first." >&2
  exit 1
}

mkdir -p "${output_dir}"
run_dir="$(mktemp -d "${output_dir}/$(date +%Y%m%d-%H%M%S)-XXXXXX")"
log_file="${run_dir}/server.log"
memory_file="${run_dir}/memory-kb.log"

server_pid=""
memory_monitor_pid=""
client_pid=""
cleanup() {
  trap - EXIT INT TERM
  local child_pid
  for child_pid in "${client_pid}" "${memory_monitor_pid}" "${server_pid}"; do
    [[ -n "${child_pid}" ]] && kill "${child_pid}" >/dev/null 2>&1 || true
  done
  for child_pid in "${client_pid}" "${memory_monitor_pid}" "${server_pid}"; do
    [[ -n "${child_pid}" ]] && wait "${child_pid}" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

"${server_bin}" --host 127.0.0.1 --port "${port}" --model "${model_file}" \
  -ngl 99 --ctx-size 4096 --predict 256 --repeat-penalty 1.05 --temp 0.7 \
  >"${log_file}" 2>&1 &
server_pid=$!
(
  while kill -0 "${server_pid}" >/dev/null 2>&1; do
    ps -o rss= -p "${server_pid}" >>"${memory_file}" || true
    sleep 0.1
  done
) &
memory_monitor_pid=$!

ready=false
for _ in {1..30}; do
  kill -0 "${server_pid}" 2>/dev/null || {
    echo "Native speech server exited before becoming ready. See ${log_file}" >&2
    tail -n 30 "${log_file}" >&2
    exit 1
  }
  if curl --noproxy '*' --max-time 2 --silent --fail "http://127.0.0.1:${port}/health" >/dev/null; then
    ready=true
    break
  fi
  sleep 1
done
[[ "${ready}" == true ]] || { echo "Server readiness timed out: ${log_file}" >&2; exit 1; }

init_started="${EPOCHREALTIME}"
curl --noproxy '*' --max-time 180 --fail-with-body --silent --show-error \
  -H 'Content-Type: application/json' \
  -d "$(jq -n --arg model_dir "${model_dir}" --arg output_dir "${run_dir}" \
    --arg voice_prompt $'<|im_start|>system\n模仿音频样本的音色并生成新的内容。\n<|audio_start|>' \
    --arg assistant_prompt $'<|audio_end|>你是 EVA，一个真诚、年轻、有自己判断的女性 AI 朋友。说话要像真实聊天，自然、口语化、克制，一般只说一到三句。你不是心理咨询师或客服，不要套话，不要列表，不要念表情或动作标签。<|im_end|>\n<|im_start|>user\n' \
    '{media_type:2,use_tts:true,duplex_mode:false,model_dir:$model_dir,tts_bin_dir:($model_dir + "/tts"),tts_gpu_layers:100,token2wav_device:"gpu:0",output_dir:$output_dir,voice_clone_prompt:$voice_prompt,assistant_prompt:$assistant_prompt}')" \
  "http://127.0.0.1:${port}/v1/stream/omni_init" >"${run_dir}/init.json"

# Initialize the native voice-cloning system prompt with the bundled reference
# voice, then submit the real user turn as text through the same omni pipeline.
curl --noproxy '*' --max-time 180 --fail-with-body --silent --show-error \
  -H 'Content-Type: application/json' \
  -d "$(jq -n --arg audio "${reference_audio}" '{audio_path_prefix:$audio,cnt:0}')" \
  "http://127.0.0.1:${port}/v1/stream/prefill" >"${run_dir}/voice-prefill.json"

initialization_ms=$(( (${EPOCHREALTIME} - init_started) * 1000 ))
# SSE completion describes text only. The client also waits for the vocoder's
# completion flag and validates every PCM chunk before accepting a result.
python3 "${project_dir}/Research/NativeSpeech/benchmark_turns.py" \
  --url "http://127.0.0.1:${port}" --run-dir "${run_dir}" \
  --initialization-ms "${initialization_ms}" "$@" &
client_pid=$!
wait "${client_pid}"
client_pid=""
