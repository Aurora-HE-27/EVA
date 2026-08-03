# EVA（macOS）

EVA 是一个以 Mac 本地能力为核心、可选接入大模型 API 的虚拟伴侣：

- SwiftUI 原生界面
- 本地 Ollama / OpenAI Chat Completions 兼容 API 一键切换
- API 密钥仅保存在 macOS 钥匙串，不写入项目或偏好文件
- macOS 设备端中文语音识别
- 本地 Qwen3-TTS（MLX）原创声线，失败时回退 macOS 系统语音
- 用户打断和停止播放
- 结构化情绪协议驱动形象、状态色彩与声音语气
- 支持导入原创或已授权的写实成年人物肖像
- 内置一位 AI 原创的年轻成年 EVA 默认形象
- 真人肖像舞台、微动作、音频光环和状态氛围动画
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

## 真人形象

打开右上角设置，点击“选择图片…”导入一张干净的竖版成年人物肖像。建议：

- 2:3 竖图，至少 1024 × 1536
- 正脸或轻微侧脸，嘴巴闭合，脸部无遮挡
- 头、肩和上半身完整，背景简单
- 只使用原创、本人或明确获得授权的形象

当前版本根据 EVA 输出的 `emotion / valence / arousal / intensity` 控制单张肖像的呼吸、视线漂移、姿态、亮度、饱和度和状态色彩，并让同一段情绪数据同步影响声音。真正的眼睑、眉形和逐音素口型仍需要后续接入 talking-head 推理引擎。

默认角色图位于 `Resources/Assets/EVA-Portrait-Young-v1.png`，由图像模型原创生成，不对应任何真人。用户仍可以在设置中导入本人、原创或明确获得授权的替代形象。

## 声音

“EVA · 原创声线”使用适用于 Apple Silicon 的 MLX-Audio 与 Qwen3-TTS VoiceDesign，根据文字描述实时生成，不采集或克隆任何真人声音。App 会尝试启动本机 `~/.local/bin/mlx_audio.server`，复用已加载模型；运行环境不可用时自动回退到 Mac 中文语音。

原创声音设计样本位于 `Resources/Audio/EVA-Voice-Preview-v1_000.wav`。本机运行环境：

```bash
brew install uv
brew install python@3.12
uv tool install --python /opt/homebrew/bin/python3.12 --force 'mlx-audio[server]' --prerelease=allow
```

首次使用会下载 `mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16`，后续会复用本地模型缓存。EVA 会根据每次回复的情绪动态补充声线指令；系统声音回退也会相应调整语速和音高。

EVA 将 Hugging Face 权重统一保存在以下独立目录，不会放入项目或提交到 GitHub：

```text
/Users/hewenkai/AI开发/ai模型/huggingface
```

可以在 EVA 设置中查看并用 Finder 打开该目录。命令行管理缓存时使用：

```bash
HF_HOME='/Users/hewenkai/AI开发/ai模型/huggingface' \
  ~/.local/share/uv/tools/mlx-audio/bin/hf cache ls
```

目前此目录约占 4.2 GB，只包含 Qwen3-TTS。后续语音情绪识别、Audio2Face 或真人驱动模型也必须复用同一个 `HF_HOME`，不在项目、`~/.cache` 或其他位置重复保存。`~/AI开发/ai模型/services` 用于未来本地推理服务的配置和日志，不存 Git 历史。

## 文字模型切换

打开右上角设置，在“文字模型来源”中选择：

- **本地 Ollama**：对话不离开 Mac，继续使用本机模型。
- **大模型 API**：填写 HTTPS 根地址或完整端点、模型名称和 API 密钥。EVA 会自动为 DeepSeek 根地址及常见 `/v1` 根地址补全 Chat Completions 路径。

API 模式只替换最耗算力的文字生成。语音识别、形象、情绪表现和 Qwen3-TTS 仍在本机执行。对话正文会发送给所选服务商，因此服务商的隐私政策与费用由用户自行确认。切回 Ollama 不会删除 API 配置。

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

## 真人表情路线

本版本先完成稳定的情绪总线和可替换渲染层，没有下载尚不能完整运行的视觉权重。当前 Apple Silicon 路线评估：

- **MuseTalk 1.5 MLX q4**：权重体积和推理速度有吸引力，但现有 Swift 移植仍缺音频管线与人脸预处理，暂不作为可用功能发布。
- **LivePortrait**：官方支持 Apple Silicon，但官方给出的 Mac 速度明显不适合实时语音对话，更适合作为离线高质量模式。
- **ARKit 兼容 BlendShape / Audio2Face**：适合作为实时层。下一版优先把音频转换为口型与面部参数，再让这些参数驱动可变形真人头像；之后才加入高质量神经渲染模式。

这样可以保留本版本的 `AppState`、情绪协议和语音流水线，只替换 `AvatarStageView` 下方的渲染实现。
