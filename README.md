# 虚拟伴侣（macOS）

一个完全在 Mac 上运行的虚拟伴侣 MVP：

- SwiftUI 原生界面
- Ollama 流式文字对话
- macOS 设备端中文语音识别
- macOS 系统语音合成
- 用户打断和停止播放
- 会呼吸、眨眼、说话和切换状态的占位角色
- 支持导入原创或已授权的写实成年人物肖像
- 真人肖像舞台、音频光环和状态氛围动画
- 中文声音质量排序、语速、音高和试听
- 对话本地持久化

## 环境

- macOS 14 或更高版本
- Apple Silicon
- Xcode 16 或更高版本
- 已安装并启动 Ollama
- 至少下载一个 Ollama 对话模型

## 开发运行

```bash
swift run
```

开发运行方式没有 `.app` 权限描述，首次测试麦克风建议使用下方的应用打包方式。

## 打包与启动

```bash
chmod +x scripts/package_app.sh
./scripts/package_app.sh
open dist/VirtualCompanion.app
```

首次使用语音时，macOS 会询问麦克风和语音识别权限。

## 真人形象

打开右上角设置，点击“选择图片…”导入一张干净的竖版成年人物肖像。建议：

- 2:3 竖图，至少 1024 × 1536
- 正脸或轻微侧脸，嘴巴闭合，脸部无遮挡
- 头、肩和上半身完整，背景简单
- 只使用原创、本人或明确获得授权的形象

当前版本对单张肖像提供呼吸、景深、状态色彩与语音光环。真正逐音素口型需要后续接入 talking-head 推理服务。

## Ollama

默认连接：

```text
http://127.0.0.1:11434
```

应用会读取 `/api/tags` 并在设置中显示本机模型。建议优先使用 7B–9B 中文能力较好的量化模型。

## 下一阶段

当前角色由 SwiftUI 程序绘制，`AvatarView` 已经与监听、思考和说话状态解耦。接入 Live2D 时，可以保留 `AppState` 和语音流水线，仅把 `AvatarView` 换为 `WKWebView`/Cubism 渲染器。
