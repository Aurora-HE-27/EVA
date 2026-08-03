import AppKit
import AVFoundation
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("EVA 设置")
                .font(.system(size: 24, weight: .bold, design: .rounded))

            Form {
                TextField("Ollama 地址", text: $appState.serverAddress)
                    .textFieldStyle(.roundedBorder)

                Picker("对话模型", selection: $appState.selectedModel) {
                    if appState.models.isEmpty {
                        Text("没有检测到模型").tag("")
                    }
                    ForEach(appState.models) { model in
                        Text(model.name).tag(model.name)
                    }
                }

                Picker("中文声音", selection: $appState.selectedVoiceIdentifier) {
                    Text("EVA · 原创声线（Qwen3-TTS）")
                        .tag(SpeechOutputService.evaVoiceIdentifier)
                    Text("系统默认").tag("")
                    ForEach(
                        SpeechOutputService.availableVoices.filter {
                            $0.identifier != SpeechOutputService.evaVoiceIdentifier
                        },
                        id: \.identifier
                    ) { voice in
                        Text(voiceLabel(voice))
                            .tag(voice.identifier)
                    }
                }

                HStack {
                    Text("声音模型目录")
                    Spacer()
                    Text("~/AI开发/ai模型/huggingface")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                        .help(SpeechOutputService.huggingFaceHomeURL.path)
                    Button("显示") {
                        NSWorkspace.shared.activateFileViewerSelecting([
                            SpeechOutputService.huggingFaceHomeURL
                        ])
                    }
                }

                HStack {
                    Text("语速")
                    Slider(value: $appState.voiceRate, in: 0.38...0.56, step: 0.01)
                    Text(appState.voiceRate.formatted(.number.precision(.fractionLength(2))))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 34)
                }

                HStack {
                    Text("音高")
                    Slider(value: $appState.voicePitch, in: 0.85...1.18, step: 0.01)
                    Text(appState.voicePitch.formatted(.number.precision(.fractionLength(2))))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 34)
                }

                HStack {
                    Text("真人形象")
                    Spacer()
                    Text(appState.avatarDisplayName)
                        .foregroundStyle(.secondary)
                    Button("使用默认") {
                        appState.useBundledAvatar()
                    }
                    .disabled(appState.avatarDisplayName == "EVA 原创形象")
                    Button("选择图片…") {
                        appState.chooseAvatarImage()
                    }
                }
            }
            .formStyle(.grouped)

            Text("默认形象与 Qwen3-TTS 声线均由 AI 原创，不对应或克隆任何真人。原创声线不可用时会自动回退到 Mac 本机中文语音。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            HStack {
                Button("重新检测模型") {
                    Task { await appState.refreshModels() }
                }

                Button("试听声音") {
                    appState.previewVoice()
                }

                Spacer()

                Button("取消") {
                    dismiss()
                }

                Button("保存") {
                    Task {
                        await appState.saveSettings()
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
    }

    private func voiceLabel(_ voice: AVSpeechSynthesisVoice) -> String {
        let quality: String
        switch voice.quality {
        case .premium:
            quality = "高级"
        case .enhanced:
            quality = "增强"
        default:
            quality = "标准"
        }
        return "\(voice.name) · \(voice.language) · \(quality)"
    }
}
