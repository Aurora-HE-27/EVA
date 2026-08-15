import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @State private var companionName = "EVA"
    @State private var userName = ""
    @State private var gender = CompanionGender.feminine
    @State private var personality = PersonalityPreset.gentle
    @State private var isCompleting = false

    var body: some View {
        HStack(spacing: 0) {
            identityPanel
            Divider()
            configurationPanel
        }
        .frame(minWidth: 920, minHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var identityPanel: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.indigo, .pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "sparkles")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 92, height: 92)

            VStack(alignment: .leading, spacing: 10) {
                Text("创造只属于你的伴侣")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("姓名、性格与声音风格都会真正改变对话方式。所有设定与聊天只保存在这台 Mac。")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
            }

            Label("完全离线 · 无账户 · 无订阅", systemImage: "lock.shield.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(.green)

            Spacer()
        }
        .padding(48)
        .frame(width: 390)
        .background(.indigo.opacity(0.055))
    }

    private var configurationPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("初次见面")
                    .font(.system(size: 26, weight: .bold, design: .rounded))

                VStack(alignment: .leading, spacing: 8) {
                    Text("伴侣叫什么？")
                        .font(.headline)
                    TextField("例如：EVA、小雨、阿澈", text: $companionName)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("希望怎么称呼你？（可选）")
                        .font(.headline)
                    TextField("你的名字或昵称", text: $userName)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("性别表达")
                        .font(.headline)
                    Picker("性别表达", selection: $gender) {
                        ForEach(CompanionGender.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("最重要的性格")
                        .font(.headline)
                    LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 10) {
                        ForEach(PersonalityPreset.allCases) { option in
                            Button {
                                personality = option
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(option.displayName)
                                        .font(.headline)
                                    Text(option.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                }
                                .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
                                .padding(12)
                                .background(
                                    personality == option
                                        ? Color.indigo.opacity(0.14)
                                        : Color(nsColor: .controlBackgroundColor),
                                    in: RoundedRectangle(cornerRadius: 12)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(
                                            personality == option ? Color.indigo : .clear,
                                            lineWidth: 1.5
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                HStack {
                    Text("之后可以在设置中继续调整声音。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(isCompleting ? "正在准备…" : "开始陪伴") {
                        finish()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(
                        companionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || isCompleting
                    )
                }
                .padding(.top, 4)
            }
            .padding(42)
        }
    }

    private func finish() {
        isCompleting = true
        let profile = CompanionProfile(
            name: companionName,
            gender: gender,
            personality: personality,
            userName: userName
        )
        Task {
            await appState.completeOnboarding(with: profile)
            isCompleting = false
        }
    }
}
