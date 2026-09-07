# EVA Native Speech Lab

This lab evaluates whether MiniCPM-o 4.5 can replace EVA's current
`Qwen3.5 2B -> Qwen3-TTS 0.6B` cascade with its integrated text/speech pipeline.
MiniCPM-o still has a language backbone, a conditioned speech decoder and a
vocoder. Its speech path uses language-model hidden states as well as text;
"native speech" does not mean it has no internal modules or that it must sound
more human. We evaluate that separately by listening.

It is experimental and does not change the production app. The current app
remains the rollback-safe baseline until this lab passes all gates below.

## Target machine and mode

- Apple M4 Pro, 24 GB unified memory
- simplex, turn-based interaction
- text input -> synchronized speech and transcript output
- no camera or microphone input, Docker, or Ollama

The pinned HTTP runtime validates and loads the vision component even in this
text-only experiment, so the current reproducible model set includes it. No
images or video are submitted.

The selected Q4_K_M runtime set is about 8.9 GB on disk. Model weights
live under `.eva-models/huggingface/openbmb/MiniCPM-o-4_5-gguf`; the compiled
runtime lives under `.eva-runtime/llama.cpp-omni`. Both directories are ignored
by Git and can be reconstructed from the pinned manifests and scripts.

The pinned `llama-omni-server` already accepts text through its native
`stream_prefill` path. EVA therefore does not patch model math or insert an
external TTS layer.
Two small, tracked compatibility patches fix loopback binding, the lifetime and
termination of the HTTP response stream, error notification, and speech flushing
at the generation limit. `setup_native_speech_lab.sh` applies them idempotently.
The lab uses HTTP on `127.0.0.1` with OpenSSL disabled at build time; it is not a
LAN or production web service.

## Reproduce

Requires Apple command-line build tools, CMake, Git, curl, jq and Python 3.9+.
No Python packages, model service accounts or paid API keys are required.

```bash
./scripts/setup_native_speech_lab.sh
./scripts/download_native_speech_models.sh
./scripts/benchmark_native_speech.sh
# Or pass one or more custom user turns:
./scripts/benchmark_native_speech.sh "今天发生了件挺好笑的事。" "你想听吗？"
```

The default is three consecutive Chinese turns in one model session. Results,
transcripts and playable `round_XXX/reply.wav` files are written under
`Artifacts/NativeSpeech/`, which is excluded from Git. Custom prompts may be
private: do not commit raw logs or audio without reviewing them.

Downloads are pinned to `Models.lock.json` and verified against the repository's
LFS SHA-256 hashes in `SHA256SUMS`. All ten files have been verified locally.

Timing starts before the user text is submitted. The first-audio measurement
detects a complete PCM chunk every 20 ms; it excludes model initialization and
does not measure speaker hardware latency or leading silence. Total generation
time waits for both the text stream and the vocoder's completion flag, validates
all expected WAV chunks, and only then stops the server. The benchmark separately
reports initialization time and distinguishes the first turn from warmed turns.
Reported RSS is process-resident memory, not a measurement of all system/Metal
memory. Full memory-pressure and listening validation remain promotion gates.

Protocol/WAV regression tests (no models required):

```bash
python3 -m unittest discover -s Research/NativeSpeech -p 'test_*.py'
```

See [M4 Pro measurements](M4_PRO_RESULTS.md) for the current result and limits.

## Promotion gates

The experiment may replace the baseline only if it demonstrates all of:

1. Mandarin output has no language drift or obvious pronunciation errors in
   a 30-turn evaluation set.
2. The first playable audio arrives in at most 2.5 seconds after warm-up.
3. Real-time factor is below 1.0 for ordinary one-to-three-sentence replies.
4. Peak resident memory remains below 18 GB with EVA open.
5. Text and audio represent the same response, without dropped or duplicated
   fragments.
6. Blind listening is preferred to the current Qwen3-TTS baseline in at least
   70% of paired samples.

Until those conditions are met, MiniCPM-o remains research code only.

## Upstream references

- [OpenBMB MiniCPM-o documentation](https://github.com/OpenBMB/MiniCPM-V/blob/main/README_zh.md)
- [Pinned GGUF model repository](https://huggingface.co/openbmb/MiniCPM-o-4_5-gguf/tree/db25077c33951fe163b42986fba0132e279872a2)
- [Pinned native runtime](https://github.com/tc-mb/llama.cpp-omni/tree/164819778518de000de2d2e323147d8d1ac4bc5c)
