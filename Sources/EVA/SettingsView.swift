import AppKit
import AVFoundation
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var openingSnapshot: AppSettingsSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("EVA 设置")
                .font(.system(size: 24, weight: .bold, design: .rounded))

            Form {
                LabeledContent("当前伴侣") {
                    Text("\(appState.profile.sanitizedName) · \(appState.profile.gender.displayName) · \(appState.profile.personality.displayName)")
                }

                LabeledContent("对话核心") {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(appState.isLocalModelReady ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)
                        Text("Qwen3.5 0.8B · 4-bit · MLX")
                    }
                }

                LabeledContent("隐私模式") {
                    Label("完全本地，无网络权限", systemImage: "lock.shield.fill")
                        .foregroundStyle(.green)
                }

                Picker("中文声音", selection: $appState.selectedVoiceIdentifier) {
                    Text("系统默认").tag("")
                    ForEach(SpeechOutputService.availableVoices, id: \.identifier) { voice in
                        Text(voiceLabel(voice)).tag(voice.identifier)
                    }
                }

                HStack {
                    Text("AI 模型目录")
                    Spacer()
                    Text("~/AI开发/ai模型/huggingface")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                        .help(ModelStorage.huggingFaceURL.path)
                    Button("显示") {
                        NSWorkspace.shared.activateFileViewerSelecting([
                            ModelStorage.huggingFaceURL
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
            }
            .formStyle(.grouped)

            Text("对话、历史记录、语音识别与语音合成都在这台 Mac 上完成。EVA 不包含 API 密钥，也不会将对话发送到网络。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            HStack {
                Button("试听声音") {
                    appState.previewVoice()
                }

                Spacer()

                Button("取消") {
                    if let openingSnapshot {
                        appState.restoreSettings(openingSnapshot)
                    }
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
        .onAppear {
            openingSnapshot = appState.settingsSnapshot()
        }
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
