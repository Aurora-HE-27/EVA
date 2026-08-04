# EVA（macOS）

EVA 是一个以 Mac 本地能力为核心、可选接入大模型 API 的虚拟伴侣：

- SwiftUI 原生界面
- 本地 Ollama / OpenAI Chat Completions 兼容 API 一键切换
- API 密钥仅保存在 macOS 钥匙串，不写入项目或偏好文件
- macOS 设备端中文语音识别
- 本地 Qwen3-TTS（MLX）原创声线，失败时回退 macOS 系统语音
- 用户打断和停止播放
- 结构化情绪协议驱动声音语气和轻量状态反馈
- EVA 温柔自然声线预设、中文声音选择、语速、音高和试听
- 对话本地持久化

## 环境

- macOS 14 或更高版本
- Apple Silicon
- Xcode 16 或更高版本
- 文字生成二选一：已安装并启动 Ollama，或拥有 OpenAI Chat Completions 兼容 API

## 开发运行

```bash
swift run
```

开发运行方式没有 `.app` 权限描述，首次测试麦克风建议使用下方的应用打包方式。

## 打包与启动

```bash
chmod +x scripts/package_app.sh
./scripts/package_app.sh
open dist/EVA.app
```

首次使用语音时，macOS 会询问麦克风和语音识别权限。

## 当前产品范围

0.5.0 暂停真人画面生成，将产品主线收敛为对话、语音、记忆和情绪表达。原因是通用单图口型模型会产生身份漂移、牙齿闪烁和下半脸模糊，现阶段达不到 EVA 的类真人质量标准，也不适合作为未来 iPhone 版本的必要运行依赖。

界面现在使用单栏对话布局和轻量状态标识，不再加载、生成或播放人物视频。原始 EVA 角色图仍作为后续品牌与专属数字人研究素材保留在 `Resources/Assets`，当前 App 不使用它进行人脸推理。

## 声音

“EVA · 原创声线”使用适用于 Apple Silicon 的 MLX-Audio 与 Qwen3-TTS VoiceDesign，根据文字描述实时生成，不采集或克隆任何真人声音。App 会尝试启动本机 `~/.local/bin/mlx_audio.server`，复用已加载模型；运行环境不可用时自动回退到 Mac 中文语音。

原创声音设计样本位于 `Resources/Audio/EVA-Voice-Preview-v1_000.wav`。本机运行环境：

```bash
brew install uv
brew install python@3.12
uv tool install --python /opt/homebrew/bin/python3.12 --force 'mlx-audio[server]' --prerelease=allow
```

首次使用会下载 `mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16`，后续会复用本地模型缓存。EVA 会根据每次回复的情绪强度、效价和唤醒度动态补充声线指令；系统声音回退也会相应调整语速和音高。

EVA 将 Hugging Face 权重统一保存在以下独立目录，不会放入项目或提交到 GitHub：

```text
/Users/hewenkai/AI开发/ai模型/huggingface
```

可以在 EVA 设置中查看并用 Finder 打开该目录。命令行管理缓存时使用：

```bash
HF_HOME='/Users/hewenkai/AI开发/ai模型/huggingface' \
  ~/.local/share/uv/tools/mlx-audio/bin/hf cache ls
```

正式运行只需要 Qwen3-TTS VoiceDesign bf16。此前试验过的视觉模型不再属于当前 App 依赖；项目和 GitHub 均不包含任何模型权重或 Python 虚拟环境。

## 文字模型切换

打开右上角设置，在“文字模型来源”中选择：

- **本地 Ollama**：对话不离开 Mac，继续使用本机模型。
- **大模型 API**：填写 HTTPS 根地址或完整端点、模型名称和 API 密钥。EVA 会自动为 DeepSeek 根地址及常见 `/v1` 根地址补全 Chat Completions 路径。

API 模式只替换最耗算力的文字生成。语音识别、情绪控制和 Qwen3-TTS 仍在本机执行。对话正文会发送给所选服务商，因此服务商的隐私政策与费用由用户自行确认。切回 Ollama 不会删除 API 配置。

本地开发包使用稳定的 designated requirement 签名，避免每次重新构建都改变钥匙串访问身份。0.4.1 从旧版临时签名迁移到新的稳定钥匙串条目，需要用户在设置中重新粘贴一次 API 密钥；旧条目保持不动，不会被程序导出或删除。

EVA 要求文字模型在正文前输出一行内部情绪控制信息。该行会被流式解析器截获，不会显示在聊天记录或被朗读；即使第三方模型没有遵守协议，EVA 也会保留正文并用本地规则推断基础情绪。

## Ollama

默认连接：

```text
http://127.0.0.1:11434
```

应用会读取 `/api/tags` 并在设置中显示本机模型。建议优先使用 7B–9B 中文能力较好的量化模型。

当前项目提供了一个修正第三方 Qwen3 思考模板的 EVA 派生模型。它复用已有权重，不会复制模型文件：

```bash
ollama stop eva 2>/dev/null || true
ollama create eva -f Ollama/EVA.Modelfile
```

创建后重新打开应用，EVA 会自动优先选择并记住 `eva:latest`。如果设置中仍保存着原始故障模型，应用也会自动迁移。直接选择原始的 `Qwen3-14B-Uncensored-GGUF` 可能因为其 GGUF 聊天模板缺陷而只返回思考内容、没有最终正文。

## iPhone 产品路线

当前优先级是把核心能力拆成可复用 Swift 模块，再建立正式的 iOS App target：

```text
DeepSeek API / 本地兼容服务（文字与情绪）
  → iPhone 设备端语音识别
  → 流式文本与记忆
  → 设备端或可下载的轻量声音层
  → 原生 SwiftUI 对话界面
```

真人画面只有在专属 EVA 模型能够稳定保持身份、授权适合发布，并能转换为 Core ML 在 iPhone 上达到可接受功耗后才重新进入产品主线。RTX PRO 6000 可用于一次性训练和蒸馏，发布后的 App 不依赖按分钟数字人平台。
