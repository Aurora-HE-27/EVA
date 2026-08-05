# EVA for macOS

EVA 是一款以隐私和情感支持为核心的纯本地 Mac 伴侣应用。对话、记忆、语音识别和语音合成都在设备上完成，App Sandbox 不申请网络权限。

## 0.6.1 能力

- SwiftUI 原生 macOS 应用
- Swift + MLX + Metal 直接运行 Qwen3.5 0.8B 4-bit
- 首次启动可设定伴侣姓名、性别表达、性格和用户称呼
- 人格配置直接进入本地系统提示词，并联动语速与音高
- 流式文字生成与多轮上下文
- 独立的本地情绪辅助层，用于界面状态和声音语气
- macOS 设备端中文语音识别
- macOS 离线中文语音合成，可调节语速和音高
- 对话仅保存在用户本机 Application Support 目录
- 无 API 密钥、无 Ollama、无 Python 运行时依赖

## 运行要求

- Apple Silicon Mac
- macOS 14 或更高版本

终端用户只需安装 EVA.app。Xcode、XcodeGen 和 Metal Toolchain 仅用于开发构建。
Swift Package 解析结果保存在 `Package.resolved`，发布构建不会自动漂移到未经验证的新依赖版本。

## 开发模型位置

模型权重不提交到 GitHub，统一保存在：

```text
/Users/hewenkai/AI开发/ai模型/huggingface/mlx-community/Qwen3.5-0.8B-MLX-4bit
```

构建脚本会将该目录作为资源复制到 EVA.app，用户运行时不需要单独下载或配置模型。可使用 `EVA_MODEL_SOURCE` 指定其他开发路径。

Qwen3.5 权重使用 Apache 2.0 许可；MLX Swift LM 使用 MIT 许可。发布前需将完整许可文本加入 App 的 acknowledgements。

## 构建

```bash
./scripts/package_app.sh
open dist/EVA.app
```

开发模型基准和单元测试：

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

## 产品路线

1. 已完成：本地文字生成、情绪协议与安全基线
2. 已完成：初始化性别、名字、性格与声音风格
3. 进行中：分层长期记忆与用户可见的删除控制
4. 设备端专用语音模型和更自然的韵律层
5. 免费内测、隐私审核、Mac App Store 一次性买断发布

真人画面不在当前产品主线内，只有在身份一致性、功耗和商业授权都达到发布标准后才会重新评估。
