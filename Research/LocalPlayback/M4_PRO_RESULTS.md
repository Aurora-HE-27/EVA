# EVA 0.12.0 — 本地播放流水线验证

日期：2026-09-07。设备：用户的 M4 Pro / 24GB Mac。

## 本轮范围

主程序继续使用仓库锁定的 Qwen3.5-2B MLX 4-bit 与
Qwen3-TTS 0.6B CustomVoice 4-bit，没有新下载模型或接入云服务。
用户输入文字；EVA 的完整短答保留语音上下文，长答最多分成两个完整语义段。
语音模型保留在内存中；下一段合成与前段播放重叠。

字幕与声音共用不可变分段计划。只有实际开始播放的段落可恢复到聊天历史，
正常播放在该段开口约 450ms 后显示字幕；手动停止会立即结算已开始的段落。
这是片段级处理，不是逐字时间对齐，也不表示该段每个字都已被听完。

## 验证结果

最终回归：75 项测试，0 失败。包括：

- 完整句分段、短接话合并、引号/标点/数字边界；
- 已开始与已显示两种字幕前缀、取消、重播、历史恢复；
- 真 AVAudioEngine 渲染时钟：有序播放、迟到片段、同 ID 重播隔离；
- 实际 MLX 中文生成、语音有效性、取消后同模型继续使用；
- 实际本地语音生成到音频队列的两段测试。

所有自动音频播放测试使用静音节点：验证的是音频时钟和生命周期，
不是自动评价主观听感。自然度仍须用户试听。

打包后的 EVA 0.12.0（build 18）通过签名校验，未包含 XCTest 组件；
沙盒权限没有网络或麦克风访问。另在成品应用中完成文字发送、准备期间
隐藏回复、进入语音播放后显示字幕、播放结束恢复待机，以及重播后打断
的界面验证。使用原有本地神经语音设置，未清空或上传用户聊天记录。

最终运行的两段语音测试（已预加载语音权重，不含语言模型回答时间）：

| 事件 | 从开始合成算起 |
| --- | ---: |
| 第一段音频生成完成 | 2.361 秒 |
| 第一段进入可听样本位置 | 2.449 秒 |
| 第二段音频生成完成 | 3.925 秒 |
| 第二段进入可听样本位置 | 7.733 秒 |
| 全部播放完成 | 12.235 秒 |

本例第二段在前段结束前已准备好，估算生成饥饿等待为 0 秒。
不代表任意文本、语速或其他 Mac 都不会等待。原音频自身的停顿仍保留。
两次连续短句测试中，暖模型一轮生成 2.560 秒音频耗时 0.927 秒。
这些是单次采样结果，不是固定语料、多次 A/B 性能结论。

取消验证：首次完整回归测得 0.373 秒，最终回归测得约 0.001 秒，
说明取消耗时受取消发生在 GPU 步骤中的位置影响；不能中断已提交的单个 GPU 运算。

## 暂不启用句内 PCM 流式输出的原因

当前 vendored Swift decoder 与官方的注意力 mask / 位置编码实现存在差异。
其 `generateStream` 是 token 进度加最终整段音频，不是逐块 PCM。
直接前缀解码并切出新增波形，无法保证先前波形不因后续 token 改变。
本轮不修改已能生成语音的 decoder 数学实现，也不将完整句分段包装成端到端语音。

下一步应单独建立 decoder 与官方参考的一致性测试，通过后再评估真正的句内音频流。
源代码审查记录见 `Vendor/swift-qwen3-tts/UPSTREAM.md`。

## 复现

在已完成模型恢复的项目目录运行（测试不联网）：

```sh
xcodegen generate
xcodebuild -project EVA.xcodeproj -scheme EVA -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath DerivedData \
  -disableAutomaticPackageResolution -skipPackagePluginValidation -skipMacroValidation \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES \
  EVA_SKIP_MODEL_EMBED=1 ARCHS=arm64 ONLY_ACTIVE_ARCH=YES test
```

构建系统缓存可能需要正常 Xcode 文件权限。测试宿主不加载用户聊天记录，
测试代码自行加载本地模型。完整日志位于被 Git 忽略的 `Artifacts/*.log`。

参考的排队/交互思路：
[Hugging Face speech-to-speech](https://github.com/huggingface/speech-to-speech)、
[天工开帧语音插件](https://github.com/beiyege-01/dsh-voice-ai-girlfriend-plugin)。
本轮实现为独立 Swift 代码，没有复制其服务或新增平台依赖。
