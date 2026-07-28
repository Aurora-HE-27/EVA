import AppKit
import SwiftUI

struct AvatarStageView: View {
    let state: AvatarState
    let isSpeaking: Bool
    let imagePath: String

    private var portrait: NSImage? {
        guard !imagePath.isEmpty else { return nil }
        return NSImage(contentsOfFile: imagePath)
    }

    var body: some View {
        if let portrait {
            PhotorealAvatarView(
                portrait: portrait,
                state: state,
                isSpeaking: isSpeaking
            )
        } else {
            ZStack(alignment: .topTrailing) {
                AvatarView(state: state, isSpeaking: isSpeaking)

                Label("在设置中导入真人肖像", systemImage: "photo.badge.plus")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(16)
            }
        }
    }
}

private struct PhotorealAvatarView: View {
    let portrait: NSImage
    let state: AvatarState
    let isSpeaking: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let breathingScale = 1.025 + sin(time * 1.25) * 0.004
            let thinkingDrift = state == .thinking ? sin(time * 0.7) * 4 : 0

            ZStack {
                Color.black

                Image(nsImage: portrait)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(breathingScale)
                    .offset(x: thinkingDrift)
                    .saturation(state == .concerned ? 0.82 : 1)
                    .brightness(state == .listening ? 0.035 : 0)
                    .animation(.easeInOut(duration: 0.5), value: state)

                LinearGradient(
                    colors: [
                        .black.opacity(0.08),
                        .clear,
                        .black.opacity(0.58)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                RadialGradient(
                    colors: [
                        Color.cyan.opacity(state == .listening ? 0.11 : 0.035),
                        .clear
                    ],
                    center: .center,
                    startRadius: 5,
                    endRadius: 330
                )

                VStack {
                    Spacer()
                    VoiceOrb(state: state, isSpeaking: isSpeaking, time: time)
                    statusPill
                        .padding(.top, 18)
                        .padding(.bottom, 28)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("真人虚拟伴侣，\(state.statusText)")
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .shadow(color: statusColor, radius: 6)
            Text(state.statusText)
                .font(.system(size: 13, weight: .medium, design: .rounded))
        }
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var statusColor: Color {
        switch state {
        case .idle: .mint
        case .listening: .cyan
        case .thinking: .yellow
        case .speaking: .pink
        case .happy: .green
        case .concerned: .orange
        }
    }
}

private struct VoiceOrb: View {
    let state: AvatarState
    let isSpeaking: Bool
    let time: Double

    var body: some View {
        let active = isSpeaking || state == .listening || state == .thinking
        let pulse = active ? 1 + abs(sin(time * 3.4)) * 0.09 : 1

        ZStack {
            Circle()
                .stroke(Color.cyan.opacity(0.15), lineWidth: 1)
                .frame(width: 112, height: 112)
                .scaleEffect(pulse * 1.18)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.cyan.opacity(0.42),
                            Color.blue.opacity(0.22),
                            Color.black.opacity(0.58)
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: 54
                    )
                )
                .overlay {
                    Circle()
                        .stroke(Color.cyan.opacity(0.75), lineWidth: 1)
                }
                .frame(width: 86, height: 86)
                .shadow(color: .cyan.opacity(active ? 0.55 : 0.22), radius: active ? 20 : 9)
                .scaleEffect(pulse)

            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { index in
                    Capsule()
                        .fill(Color.cyan.opacity(0.95))
                        .frame(
                            width: 3,
                            height: barHeight(index: index, active: active)
                        )
                }
            }
        }
    }

    private func barHeight(index: Int, active: Bool) -> CGFloat {
        guard active else { return 6 }
        let phase = time * (isSpeaking ? 11 : 5) + Double(index) * 0.85
        return 7 + abs(sin(phase)) * (isSpeaking ? 17 : 10)
    }
}
