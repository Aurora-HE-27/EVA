import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showsClearConfirmation = false

    var body: some View {
        HSplitView {
            AvatarStageView(
                state: appState.avatarState,
                emotion: appState.avatarEmotion,
                isSpeaking: appState.speechOutput.isSpeaking,
                imagePath: appState.avatarImagePath
            )
            .frame(minWidth: 360, idealWidth: 440)
            .padding(18)

            VStack(spacing: 0) {
                header
                Divider().opacity(0.45)
                conversation
                composer
            }
            .frame(minWidth: 500)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $appState.showsSettings) {
            SettingsView()
                .environmentObject(appState)
                .frame(width: 640, height: 560)
        }
        .alert("清空这段对话？", isPresented: $showsClearConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                Task { await appState.clearConversation() }
            }
        } message: {
            Text("本地保存的当前对话也会被删除。")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("EVA")
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                HStack(spacing: 6) {
                    Circle()
                        .fill(appState.isChatBackendReady ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(appState.connectionStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if appState.isGenerating || appState.speechOutput.isSpeaking {
                Button {
                    appState.stopAll()
                } label: {
                    Label("停止", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
            }

            Button {
                showsClearConfirmation = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("清空对话")

            Button {
                appState.showsSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("设置")
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 15)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(appState.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }

                    if let error = appState.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(22)
            }
            .onChange(of: appState.messages) { _, messages in
                guard let last = messages.last else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 10) {
            if appState.speechInput.isListening {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .symbolEffect(.variableColor.iterative)
                    Text(appState.speechInput.transcript.isEmpty
                         ? "正在听，请说话…"
                         : appState.speechInput.transcript)
                        .lineLimit(2)
                    Spacer()
                }
                .font(.callout)
                .foregroundStyle(.cyan)
            }

            HStack(alignment: .bottom, spacing: 10) {
                Button {
                    Task { await appState.toggleListening() }
                } label: {
                    Image(systemName: appState.speechInput.isListening ? "stop.circle.fill" : "mic.fill")
                        .font(.system(size: 18))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.borderedProminent)
                .tint(appState.speechInput.isListening ? .red : .indigo)
                .help(appState.speechInput.isListening ? "停止并发送" : "开始说话")

                TextField("说点什么…", text: $appState.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .font(.body)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .onSubmit {
                        appState.sendDraft()
                    }

                Button {
                    appState.sendDraft()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .disabled(
                    appState.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || appState.isGenerating
                )
            }
        }
        .padding(18)
        .background(.bar)
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 72)
            }

            VStack(alignment: .leading, spacing: 5) {
                if message.content.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle()
                                .fill(.secondary)
                                .frame(width: 6, height: 6)
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    Text(message.content)
                        .textSelection(.enabled)
                        .lineSpacing(3)
                        .foregroundStyle(message.role == .user ? Color.white : Color.primary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(bubbleColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            if message.role != .user {
                Spacer(minLength: 72)
            }
        }
    }

    private var bubbleColor: Color {
        message.role == .user ? .indigo.opacity(0.88) : Color(nsColor: .controlBackgroundColor)
    }
}
