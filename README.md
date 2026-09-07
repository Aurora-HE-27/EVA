# EVA for macOS

EVA 是一个纯本地、以文字交流和语音回应为核心的个人 Mac 项目。用户只需打字，EVA 会先开口说话，再显示对应文字；模型、对话和构建产物都保存在项目目录中。

> 项目状态：EVA 0.12.0，本地语音播放流水线。仓库保存可重构源码、固定依赖、公开模型清单和恢复脚本，不提交数 GB 的第三方权重。当前主程序仍是本地文字模型 + 神经语音，不宣称已经实现原生端到端语音。

## 0.12.0 能力

- SwiftUI 原生 macOS 文字聊天界面
- 用户只使用文字输入，应用不申请麦克风或语音识别权限
- EVA 的新回复在真实开始播放音频后才显示字幕，避免产生“照着屏幕念”的感觉
- 启动时预加载语音模型，聊天期间保持权重就绪，不在每轮结束后卸载
- 60 字以内的短回复保持完整；较长回复最多按完整句尾分成两段，不按逗号或逐字切分
- 同一个音频队列顺序播放，前段播放期间准备后段；生成速度不足时仍可能等待，不插入人为的段间停顿
- 每段实际开始播放约 450 毫秒后才扩展对应字幕，未开始的后段不提前显示
- 如果在开口前打断，未说出的回复不会残留在对话历史中；开口后打断只保留已开始的完整语义段（不是逐字音频对齐）
- 神经语音失败会明确报错，不会静默切换为系统朗读声音
- 任意一条 EVA 消息都可以重新播放，生成或播放过程可以立即停止
- EVA 的姓名和身份固定，不再生成可替换的伴侣角色
- Swift + MLX + Metal 运行 Qwen3.5 2B 4-bit 本地文字基线
- Qwen3-TTS 0.6B 4-bit 提供当前本地神经语音基线
- 持久化对话与内部关系状态，聊天不发送到外部服务
- 朗读前移除 Emoji、动作标签、Markdown 和网址
- 当前个人开发版不申请网络、麦克风或语音识别权限
- 模型位于 `.eva-models/`，对话与设置位于 `.eva-data/`，构建缓存位于 `DerivedData/`，成品位于 `dist/`
- 首次启动需通过 macOS 文件夹选择器授权一次项目根目录；沙盒只在系统偏好中保存访问书签，不保存聊天内容

## 运行要求

- 构建目标：Apple Silicon、macOS 14 或更高版本
- 当前验证设备：M4 Pro、24GB 统一内存；其他机型的最低可用内存和响应速度尚未逐一验证
- 安装体积约 3.3GB；首次生成和首次发声会有模型预热时间

首发版本不支持 Intel Mac。Intel 机型缺少 EVA 当前 MLX/Metal 推理路径所需的性能条件，强行兼容会显著牺牲对话速度和声音质量。

终端用户只需安装 `EVA.app`。Xcode、XcodeGen 和模型目录只用于开发构建。Swift Package 解析结果保存在 `Package.resolved`，发布构建不会自动漂移到未经验证的新依赖版本。

## 从 GitHub 完整恢复

需要 Apple Silicon Mac、macOS 14 或更高版本、完整 Xcode 和
[XcodeGen](https://github.com/yonaskolb/XcodeGen)。首次恢复建议至少预留
15GB 磁盘空间。克隆后运行：

```bash
git clone --branch codex/text-voice-eva https://github.com/Aurora-HE-27/EVA.git
cd EVA
./scripts/bootstrap.sh
open dist/EVA.app
```

`bootstrap.sh` 会完成以下操作：

1. 核验 Apple Silicon、Xcode 和 XcodeGen；
2. 验证所有固定版本的公开模型文件仍可访问；
3. 将权重下载到仓库内被 Git 忽略的 `.eva-models/huggingface`；
4. 按 `Package.resolved` 解析 Swift 依赖；
5. 生成、签名并校验 `dist/EVA.app`。

模型仓库和不可变 revision 记录在 `Models.lock.json`。这意味着恢复不会
静默跟随 Hugging Face 的 `main` 分支变化。模型权重受各自第三方许可证
约束，详情见 `THIRD_PARTY_NOTICES.md`。

只下载或校验开发模型：

```bash
./scripts/download_eva_models.sh
```

构建脚本会把两套权重复制进 `EVA.app`。高级用户可通过 `EVA_MODEL_ROOT`
指定其他 Hugging Face 根目录，或分别使用 `EVA_MODEL_SOURCE` 和
`EVA_SPEECH_MODEL_SOURCE` 指定已有模型。

语言模型来自 `mlx-community/Qwen3.5-2B-MLX-4bit`。语音模型来自 `mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-4bit`，Swift 推理实现固定于上游提交，记录见 `Vendor/swift-qwen3-tts/UPSTREAM.md`。公开发行前必须再次核验所有模型与依赖许可，并在 App 内加入完整的第三方 acknowledgements。

## 构建

```bash
./scripts/package_app.sh
open dist/EVA.app
```

运行单元测试与本地模型基准：

```bash
xcodegen generate
xcodebuild \
  -project EVA.xcodeproj \
  -scheme EVA \
  -destination 'platform=macOS,arch=arm64' \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  test
```

情感动力学参数可用本机 Julia 离线验证，Julia 不会被打包进应用：

```bash
julia Research/AffectiveDynamics/simulate.jl
```

MiniCPM-o 4.5 原生语音实验与主程序隔离，不会替换当前可用版：

```bash
./scripts/setup_native_speech_lab.sh
./scripts/download_native_speech_models.sh
./scripts/benchmark_native_speech.sh
```

实验的设计、硬件边界和晋级门槛见 `Research/NativeSpeech/README.md`。它会额外下载约 8.9GB 权重，不是普通构建的必需步骤。
当前开发版位于 `codex/text-voice-eva` 分支。原生语音实测结果见
[M4 Pro 测试记录](Research/NativeSpeech/M4_PRO_RESULTS.md)；实验通过生成测试不代表已经通过自然度验收。

## 当前路线

1. 已完成：固定 EVA 身份、纯文字输入、可见文字与自动语音回复
2. 已完成：在 M4 Pro 24GB 上跑通 MiniCPM-o 4.5 连续文字输入与语音生成，建立可重现测试台
3. 当前主线：借鉴开源语音项目的语义分段、播放队列、预加载和取消机制，保持完全本地运行
4. 待验证：修复并验证 Swift 语音解码器与官方实现的一致性，再决定是否启用句内 PCM 流式输出；当前 `generateStream` 只有 token 进度，不是实时音频块
5. 后续研究：扩大中文连续聊天的自然度盲听；模型替换或微调须先通过听感验证，不默认引入云服务器
6. 计划中：加入可审计的长期经历记忆和跨会话持续状态

本轮参考了 [Hugging Face speech-to-speech](https://github.com/huggingface/speech-to-speech)
与 [天工开帧的语音插件](https://github.com/beiyege-01/dsh-voice-ai-girlfriend-plugin)
的交互及排队思路；EVA 的本轮实现为独立 Swift 代码，没有引入其服务或平台依赖。

麦克风、全双工、真人画面和 App Store 发布暂不属于当前项目范围。
