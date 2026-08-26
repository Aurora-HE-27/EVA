import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showsClearConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.45)
            conversation
            Divider().opacity(0.35)
            composer
        }
        .frame(minWidth: 620, idealWidth: 820, minHeight: 640)
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
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.indigo, .purple.opacity(0.78)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: appState.speechOutput.isSpeaking ? "waveform" : "ellipsis.message.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolEffect(
                        .variableColor.iterative,
                        isActive: appState.speechOutput.isSpeaking
                    )
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text("EVA")
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                HStack(spacing: 6) {
                    Circle()
                        .fill(appState.isChatBackendReady ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Text("\(appState.conversationPhase.statusText) · \(appState.connectionStatus)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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
                LazyVStack(spacing: 18) {
                    ForEach(visibleMessages) { message in
                        MessageRow(
                            message: message,
                            isSpeaking: appState.speakingMessageID == message.id,
                            onReplay: { appState.replay(message) },
                            onStop: { appState.stopAll() }
                        )
                        .id(message.id)
                    }

                    if let error = appState.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                            .id("error")
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 28)
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.42))
            .onAppear {
                scrollToLatest(proxy, animated: false)
            }
            .onChange(of: appState.messages) { _, _ in
                scrollToLatest(proxy, animated: true)
            }
        }
    }

    private var visibleMessages: [ChatMessage] {
        appState.messages.filter { $0.role != .system }
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let lastID = visibleMessages.last?.id else { return }
        let action = { proxy.scrollTo(lastID, anchor: .bottom) }
        if animated {
            withAnimation(.easeOut(duration: 0.18), action)
        } else {
            action()
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("你打字，EVA 会用文字和声音回复")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .bottom, spacing: 10) {
                TextField("写给 EVA…", text: $appState.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .font(.body)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
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
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .disabled(
                    appState.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !appState.isLocalModelReady
                )
                .help(appState.isGenerating || appState.speechOutput.isSpeaking ? "打断当前回复并发送" : "发送")
            }
        }
        .padding(18)
        .background(.bar)
    }
}

private struct MessageRow: View {
    let message: ChatMessage
    let isSpeaking: Bool
    let onReplay: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 9) {
            if message.role == .user {
                Spacer(minLength: 90)
            }

            if message.role == .assistant {
                avatar
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if message.content.isEmpty {
                        ProgressView()
                            .controlSize(.small)
                        Text("EVA 正在想…")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(message.content)
                            .textSelection(.enabled)
                            .lineSpacing(3)
                    }
                }
                .foregroundStyle(message.role == .user ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    message.role == .user
                        ? Color.indigo.opacity(0.9)
                        : Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )

                if message.role == .assistant, !message.content.isEmpty {
                    Button(action: isSpeaking ? onStop : onReplay) {
                        Label(
                            isSpeaking ? "停止播放" : "再听一遍",
                            systemImage: isSpeaking ? "stop.fill" : "speaker.wave.2.fill"
                        )
                        .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(isSpeaking ? Color.indigo : Color.secondary)
                }
            }

            if message.role == .assistant {
                Spacer(minLength: 90)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            message.role == .user ? "你说：\(message.content)" : "EVA 说：\(message.content)"
        )
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(.indigo.gradient)
            Image(systemName: isSpeaking ? "waveform" : "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 30, height: 30)
    }
}
