# swift-qwen3-tts upstream record

- Source: https://github.com/AtomGradient/swift-qwen3-tts
- Vendored commit: `27a5b5b2c5d55258bead2c6e851208987e1ca225`
- Commit date: 2026-02-18
- The upstream README declares the Swift implementation MIT licensed. The
  standard MIT text is retained beside this record as `LICENSE` because that
  upstream snapshot did not contain a standalone license file.
- The Qwen3-TTS base model is published by the Qwen team under Apache-2.0.

The source is vendored so EVA can use the current `mlx-swift-lm` dependency graph instead of pulling the older `mlx-swift-examples` package declared by upstream.

EVA carries one sampling correction in `Models/Qwen3.swift`: nucleus sampling now
normalizes logits with softmax before accumulating probabilities. The upstream
implementation used raw `exp(logits)`, whose threshold changes with logit offset.
