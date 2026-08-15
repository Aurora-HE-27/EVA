# EVA for macOS

EVA 是一款以隐私和情感支持为核心的纯本地 Mac 伴侣应用。文字生成、对话记录、语音识别和语音合成都在设备上完成；应用不要求安装 Ollama、Python，也不保存 API 密钥。

> 项目状态：EVA 0.10.0 已封存。仓库保存了重构应用所需的完整源码、固定依赖、公开模型版本和恢复脚本；不包含编译缓存、成品 App 或数 GB 的第三方模型权重。

## 0.10.0 能力

- SwiftUI 原生 macOS 应用，下载后即可使用
- Swift + MLX + Metal 运行 Qwen3.5 2B 4-bit 本地语言模型
- Qwen3-TTS 0.6B 4-bit 本地神经语音，提供 Serena、Vivian 与 Dylan 三种声线
- 语音优先界面：助手回复默认不显示文字，只播放连续语音
- 每轮回答只建立一次完整语音会话，避免按句重置语调与呼吸
- 点击麦克风可立即停止当前回答并开始新的语音输入
- 首次启动可设定伴侣姓名、性别表达、性格和用户称呼
- 人格配置进入本地系统提示词，并联动声线；语音采用克制自然韵律，避免逐轮注入表演式情绪指令
- 持久化 AffectiveCore：心境、焦虑、能量、信任、亲近、好奇和玩心跨轮次连续演化
- 朋友式对话行为：直接回答、庆祝、混合情绪、接梗、自然反应、陪伴和边界表达
- 多轮对话、朋友式输出闸门与本地情绪动力学
- 朗读前移除 Emoji、动作标签、Markdown 和网址，避免念出表情名称
- macOS 设备端中文语音识别
- 对话仅保存在本机 Application Support 目录
- App Sandbox 不申请网络权限

## 运行要求

- 最低：Apple Silicon M1、8GB 统一内存、macOS 14
- 推荐：M1 Pro 或更新芯片、16GB 统一内存
- 安装体积约 3.3GB；首次生成和首次发声会有模型预热时间

首发版本不支持 Intel Mac。Intel 机型缺少 EVA 当前 MLX/Metal 推理路径所需的性能条件，强行兼容会显著牺牲对话速度和声音质量。

终端用户只需安装 `EVA.app`。Xcode、XcodeGen 和模型目录只用于开发构建。Swift Package 解析结果保存在 `Package.resolved`，发布构建不会自动漂移到未经验证的新依赖版本。

## 从 GitHub 完整恢复

需要 Apple Silicon Mac、macOS 14 或更高版本、完整 Xcode 和
[XcodeGen](https://github.com/yonaskolb/XcodeGen)。首次恢复建议至少预留
15GB 磁盘空间。克隆后运行：

```bash
git clone https://github.com/Aurora-HE-27/EVA.git
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

## 产品路线

1. 已完成：纯本地文字生成、初始化人格和安全基线
2. 已完成：持续情感核心、朋友式对话行为和 Julia 离线动力学验证
3. 已完成：语音优先界面、连续语音回答、朗读净化和克制自然韵律
4. 进行中：真人参考音频驱动的 Base 声线、真正音频分块流送、自动插话检测与回声消除
5. 计划中：针对自然中文、事实边界和稳定人格的小型 LoRA 微调
6. 免费内测、隐私审核、Mac App Store 一次性买断发布

真人画面不在当前产品主线内；只有当身份一致性、功耗和商业授权都达到发布标准后才会重新评估。
