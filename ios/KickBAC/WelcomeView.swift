import SwiftUI

struct WelcomeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onContinue: () -> Void

    @State private var isExpanding = false
    @State private var isHolding = false
    @State private var holdProgress = 0.0
    @State private var rotation = 0.0
    @State private var scale = 1.0
    @State private var opacity = 1.0

    private let holdDuration = 0.55

    var body: some View {
        GeometryReader { geometry in
            let starSize = min(280, geometry.size.width * 0.7)

            ZStack {
                Color(red: 0.105, green: 0.107, blue: 0.115)

                VStack(spacing: 0) {
                    Image("KickBACWordmark")
                        .resizable().scaledToFit()
                        .frame(width: 144)
                        .padding(.top, geometry.safeAreaInsets.top + max(96, geometry.size.height * 0.13))
                        .accessibilityLabel("KickBAC")
                        .opacity(isExpanding ? 0 : 1)

                    Spacer(minLength: 32)

                    Text(isHolding ? "Keep holding…" : "Hold to start")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.bottom, geometry.safeAreaInsets.bottom + 48)
                        .opacity(isExpanding ? 0 : 1)
                }

                Button {
                    expand(in: geometry.size, starSize: starSize)
                } label: {
                    ZStack {
                        KickBACStar(progress: holdProgress, size: starSize, isExpanding: isExpanding)

                        Image("OnboardingBreath")
                            .resizable().scaledToFit()
                            .foregroundStyle(.white)
                            .frame(width: starSize, height: starSize)
                            .opacity(isExpanding ? 1 : 0)
                            .animation(.easeOut(duration: 0.12), value: isExpanding)
                    }
                    .rotationEffect(.degrees(reduceMotion ? 0 : rotation))
                    .scaleEffect(scale)
                    .frame(width: starSize + 32, height: starSize + 32)
                    .contentShape(.rect)
                }
                .buttonStyle(HoldToStartButtonStyle(duration: holdDuration, onPressingChanged: updateHold))
                .accessibilityLabel("Hold the star to start")
                .accessibilityHint("Double-tap to get started with VoiceOver.")
                .accessibilityIdentifier("welcomeHoldButton")
                .allowsHitTesting(!isExpanding)
                .zIndex(1)
            }
            .opacity(opacity)
        }
        .ignoresSafeArea()
        .sensoryFeedback(.selection, trigger: isExpanding)
    }

    private func updateHold(_ pressing: Bool) {
        guard !isExpanding else { return }
        isHolding = pressing
        withAnimation(pressing ? .linear(duration: holdDuration) : .easeOut(duration: 0.15)) {
            holdProgress = pressing ? 1 : 0
            rotation = pressing ? 100 : 0
            scale = pressing && !reduceMotion ? 1.1 : 1
        }
    }

    private func expand(in size: CGSize, starSize: CGFloat) {
        guard !isExpanding else { return }
        isExpanding = true

        if reduceMotion {
            withAnimation(.easeOut(duration: 0.18)) {
                opacity = 0
            } completion: {
                onContinue()
            }
        } else {
            withAnimation(.easeIn(duration: 0.3)) {
                rotation += 90
                // The star's solid center must cover the farthest screen corner.
                scale = Double(hypot(size.width, size.height) / (starSize * 0.2))
            } completion: {
                onContinue()
            }
        }
    }
}

struct KickBACStar: View {
    let progress: Double
    let size: CGFloat
    let isExpanding: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appearedAt = Date.now
    @State private var isVisible = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30,
                                paused: reduceMotion || !isVisible || isExpanding || scenePhase != .active)) { timeline in
            Image("OnboardingBreath")
                .resizable().scaledToFit()
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .modifier(WelcomeStarMaterial(progress: progress, size: size,
                    elapsedTime: reduceMotion ? 0 : Float(timeline.date.timeIntervalSince(appearedAt))))
        }
        .accessibilityHidden(true)
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }
}

@Animatable
private struct WelcomeStarMaterial: ViewModifier {
    var progress: Double
    let size: CGFloat
    let elapsedTime: Float

    func body(content: Content) -> some View {
        content.colorEffect(ShaderLibrary.kickBACWelcomeStar(
            .float2(Float(size), Float(size)), .float(elapsedTime), .float(Float(progress))
        ))
    }
}

private struct HoldToStartButtonStyle: PrimitiveButtonStyle {
    let duration: Double
    let onPressingChanged: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onLongPressGesture(minimumDuration: duration, maximumDistance: 60) {
                configuration.trigger()
            } onPressingChanged: { pressing in
                onPressingChanged(pressing)
            }
            .accessibilityAction { configuration.trigger() }
    }
}

#Preview("Welcome") {
    WelcomeView(onContinue: {})
        .preferredColorScheme(.dark)
}
