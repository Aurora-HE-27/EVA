# Third-party notices

EVA does not commit model weights to Git. Exact public model revisions are
recorded in `Models.lock.json` and downloaded only when a developer rebuilds the
application.

## Models

- `mlx-community/Qwen3.5-2B-MLX-4bit`, Apache-2.0, revision
  `93760be4f1f69842a46bc13dbdc0f19e291392a3`.
- `mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-4bit`, Apache-2.0, revision
  `08c72cad5e2fd0f41730c8bd1f28149585e46361`.
- `AtomGradient/Qwen3-TTS-0.6B-CustomVoice-4bit-pruned-vocab-lite`, MIT,
  revision `863a1dfc07aae0fc11c40507ba1b5aa408abc808`; EVA uses its
  `tokenizer.json` compatibility artifact.
- `openbmb/MiniCPM-o-4_5-gguf`, Apache-2.0, revision
  `db25077c33951fe163b42986fba0132e279872a2`. This optional model set is used
  only by the isolated native-speech research lab and is not bundled into the
  current EVA application.

## Source dependencies

- `AtomGradient/swift-qwen3-tts`, MIT, vendored revision
  `27a5b5b2c5d55258bead2c6e851208987e1ca225`. See
  `Vendor/swift-qwen3-tts/UPSTREAM.md`.
- `tc-mb/llama.cpp-omni`, MIT, experimental runtime revision
  `164819778518de000de2d2e323147d8d1ac4bc5c`. It is downloaded and built under
  `.eva-runtime` and is not committed or bundled into the current app.
- Swift package dependencies and exact revisions are recorded in
  `Package.resolved`. Their respective upstream licenses continue to apply.

EVA's original application source has no separate open-source license grant in
this archived snapshot. The third-party licenses above apply only to their
respective components.
