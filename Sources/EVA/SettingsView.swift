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
                Picker("文字模型来源", selection: $appState.chatBackend) {
                    ForEach(ChatBackendKind.allCases) { backend in
                        Text(backend.displayName).tag(backend)
                    }
                }
                .pickerStyle(.segmented)

                if appState.chatBackend == .ollama {
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
                } else {
                    TextField("API 根地址或完整端点", text: $appState.apiEndpointAddress)
                        .textFieldStyle(.roundedBorder)
                    TextField("API 模型名称", text: $appState.apiModelName)
                        .textFieldStyle(.roundedBorder)
                    SecureField("API 密钥", text: $appState.apiKey)
                        .textFieldStyle(.roundedBorder)
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
                    Text("AI 模型目录")
                    Spacer()
                    Text("~/AI开发/ai模型")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                        .help(ModelStorage.rootURL.path)
                    Button("显示") {
                        NSWorkspace.shared.activateFileViewerSelecting([
                            ModelStorage.rootURL
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

            Text(settingsDisclosure)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            HStack {
                Button(appState.chatBackend == .ollama ? "重新检测模型" : "检查配置") {
                    Task { await appState.refreshModels() }
                }

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

    private var settingsDisclosure: String {
        if appState.chatBackend == .compatibleAPI {
            return "可填写服务商根地址或完整 Chat Completions 端点，EVA 会自动补全常见路径。API 模式会发送对话正文；密钥只保存在 macOS 钥匙串。"
        }
        return "Ollama 对话、默认形象和 Qwen3-TTS 声音均在本机运行。原创声线不可用时会自动回退到 Mac 中文语音。"
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
