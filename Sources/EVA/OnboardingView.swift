import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @State private var userName = ""
    @State private var isCompleting = false

    var body: some View {
        HStack(spacing: 0) {
            identityPanel
            Divider()
            introductionPanel
        }
        .frame(minWidth: 880, minHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var identityPanel: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.indigo, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "waveform")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 92, height: 92)

            VStack(alignment: .leading, spacing: 10) {
                Text("EVA")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                Text("你用文字和她交流。她会把每句话显示出来，也会亲口说给你听。")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
            }

            Label("本地运行 · 对话留在这台 Mac", systemImage: "lock.shield.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(.green)

            Spacer()
        }
        .padding(48)
        .frame(width: 390)
        .background(.indigo.opacity(0.055))
    }

    private var introductionPanel: some View {
        VStack(alignment: .leading, spacing: 26) {
            Spacer()

            Text("初次见面")
                .font(.system(size: 28, weight: .bold, design: .rounded))

            VStack(alignment: .leading, spacing: 10) {
                Text("她叫 EVA")
                    .font(.title3.weight(.semibold))
                Text("EVA 的名字与身份固定，不再通过预设生成另一个角色。之后我们会把她自己的说话方式和声音逐步训练进模型。")
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("EVA 应该怎么称呼你？（可选）")
                    .font(.headline)
                TextField("你的名字或昵称", text: $userName)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Text("稍后可以在本地设置中调整声音。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(isCompleting ? "正在准备…" : "开始聊天") {
                    finish()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isCompleting)
            }

            if let error = appState.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            Spacer()
        }
        .padding(48)
    }

    private func finish() {
        isCompleting = true
        Task {
            await appState.completeOnboarding(userName: userName)
            isCompleting = false
        }
    }
}
