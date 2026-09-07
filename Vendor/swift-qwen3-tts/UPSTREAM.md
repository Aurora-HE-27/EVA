# swift-qwen3-tts upstream record

- Source: https://github.com/AtomGradient/swift-qwen3-tts
- Vendored commit: `27a5b5b2c5d55258bead2c6e851208987e1ca225`
- Commit date: 2026-02-18
- The upstream README declares the Swift implementation MIT licensed. The
  standard MIT text is retained beside this record as `LICENSE` because that
  upstream snapshot did not contain a standalone license file.
- The Qwen3-TTS base model is published by the Qwen team under Apache-2.0.

The source is vendored so EVA can use the current `mlx-swift-lm` dependency graph instead of pulling the older `mlx-swift-examples` package declared by upstream.

EVA carries a sampling correction in `Models/Qwen3.swift`: nucleus sampling now
normalizes logits with softmax before accumulating probabilities. The upstream
implementation used raw `exp(logits)`, whose threshold changes with logit offset.

EVA also adds an optional `cancellationCheck: (() throws -> Void)?` argument to
`generateCustomVoice`, `generateVoiceDesign`, and the async `generate` dispatcher.
The caller can pass `{ try Task.checkCancellation() }`; checks surround Talker
and code-predictor steps and waveform decoding. When a check is supplied, the
lazy MLX waveform is evaluated before the final check so a cancelled generation
cannot return an unevaluated obsolete reply. Cancellation is cooperative and
cannot interrupt an already-running GPU operation. The default is `nil`, keeping
existing callers and their lazy evaluation behavior compatible.

## Decoder streaming audit

The vendored `SpeechTokenizer.swift` currently calls its decoder transformer
without an attention mask and does not apply the configured rotary position
embedding. The official Qwen decoder applies rotary positions and sliding-window
causal attention:
https://github.com/QwenLM/Qwen3-TTS/blob/main/qwen_tts/core/tokenizer_12hz/modeling_qwen3_tts_tokenizer_v2.py

Consequently, prefix decoding with this vendored implementation has no guaranteed
finite look-ahead after which earlier waveform samples stop changing. Its
existing `generateStream` emits token progress followed by one final waveform;
it is not incremental PCM output. EVA does not change the decoder math or claim
sentence-internal PCM streaming in this iteration. Restoring reference decoder
parity and validating prefix/full-utterance waveform equivalence require a
separate model-quality audit before enabling that behavior.
