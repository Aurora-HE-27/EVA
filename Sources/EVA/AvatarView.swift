import SwiftUI

struct AvatarView: View {
    let state: AvatarState
    let emotion: EmotionDirective
    let isSpeaking: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let breath = sin(time * 1.8) * 3
            let mouth = isSpeaking ? 7 + abs(sin(time * 13)) * 13 : 4
            let blink = blinkAmount(at: time)

            ZStack {
                RadialGradient(
                    colors: [
                        Color(red: 0.29, green: 0.22, blue: 0.52).opacity(0.78),
                        Color(red: 0.08, green: 0.07, blue: 0.16)
                    ],
                    center: .top,
                    startRadius: 30,
                    endRadius: 420
                )

                Circle()
                    .fill(.white.opacity(0.045))
                    .frame(width: 330, height: 330)
                    .blur(radius: 1)
                    .offset(y: -45)

                character(time: time, breath: breath, mouth: mouth, blink: blink)

                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                            .shadow(color: statusColor, radius: 5)
                        Text(state.statusText)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.78))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 28)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("EVA 虚拟伴侣，\(state.statusText)")
    }

    @ViewBuilder
    private func character(time: Double, breath: Double, mouth: Double, blink: Double) -> some View {
        let listeningTilt = state == .listening ? -4.0 : 0.0
        let thinkingTilt = state == .thinking ? 4.0 : 0.0

        ZStack {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color.indigo.opacity(0.9), Color.purple.opacity(0.45)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 235, height: 300)
                .offset(y: 185 + breath)

            Ellipse()
                .fill(Color(red: 0.98, green: 0.83, blue: 0.78))
                .frame(width: 225, height: 270)
                .overlay {
                    face(mouth: mouth, blink: blink)
                }
                .overlay(alignment: .top) {
                    hair
                }
                .shadow(color: .black.opacity(0.32), radius: 22, y: 16)
                .offset(y: breath)
                .rotationEffect(.degrees(listeningTilt + thinkingTilt))
                .animation(.easeInOut(duration: 0.45), value: state)

            if state == .thinking {
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(.white.opacity(0.8))
                            .frame(width: 7, height: 7)
                            .offset(y: sin(time * 4 + Double(index)) * 3)
                    }
                }
                .offset(x: 110, y: -105)
            }
        }
    }

    private func face(mouth: Double, blink: Double) -> some View {
        VStack(spacing: 27) {
            HStack(spacing: 57) {
                eye(blink: blink)
                eye(blink: blink)
            }
            .padding(.top, 96)

            Capsule()
                .fill(Color(red: 0.64, green: 0.19, blue: 0.28))
                .frame(
                    width: emotion.emotion == .happy ? 38 : 28,
                    height: mouth + (emotion.emotion == .surprised ? 5 : 0)
                )
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(.white.opacity(isSpeaking ? 0.55 : 0))
                        .frame(width: 18, height: 3)
                        .padding(.top, 2)
                }
        }
    }

    private func eye(blink: Double) -> some View {
        ZStack {
            Capsule()
                .fill(Color(red: 0.22, green: 0.16, blue: 0.30))
                .frame(width: 25, height: max(2, 29 * blink))

            Circle()
                .fill(.white.opacity(blink > 0.35 ? 0.8 : 0))
                .frame(width: 6, height: 6)
                .offset(x: -4, y: -5)
        }
    }

    private var hair: some View {
        ZStack {
            Ellipse()
                .trim(from: 0, to: 0.62)
                .stroke(
                    LinearGradient(
                        colors: [Color(red: 0.19, green: 0.12, blue: 0.30), .indigo],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 48, lineCap: .round)
                )
                .frame(width: 205, height: 185)
                .rotationEffect(.degrees(191))
                .offset(y: -11)

            ForEach([-58.0, -28.0, 4.0, 38.0, 67.0], id: \.self) { x in
                Capsule()
                    .fill(Color(red: 0.20, green: 0.13, blue: 0.31))
                    .frame(width: 35, height: 115)
                    .rotationEffect(.degrees(x / 6))
                    .offset(x: x, y: 28 + abs(x) / 7)
            }
        }
        .frame(height: 130)
        .offset(y: -19)
        .clipped()
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

    private func blinkAmount(at time: Double) -> Double {
        let phase = time.truncatingRemainder(dividingBy: 4.2)
        if phase > 3.98 && phase < 4.12 {
            return max(0.06, abs(phase - 4.05) / 0.07)
        }
        return 1
    }
}
