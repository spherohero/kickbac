import SwiftUI

struct PartyTapIllustration: View {
    static let instruction = "Tap your phone to the breathalyzer"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 20) {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let showsStaticPose = reduceMotion
            let repeats = !reduceMotion && scenePhase == .active

            ZStack(alignment: .topLeading) {
                Image("PartyBreathalyzer").resizable().scaledToFit()
                    .foregroundStyle(.white.opacity(contrast == .increased ? 0.65 : 0.4))
                    .frame(width: width * 0.98, height: width * 0.98)
                    .position(x: width * 0.47, y: height * 0.3)

                Image("PartyNFC").resizable().scaledToFit()
                    .foregroundStyle(Color("SplashBackground"))
                    .frame(width: width * 0.11, height: width * 0.11)
                    .position(x: width * 0.61, y: height * 0.3)

                Image("PartyPhone").resizable().scaledToFit()
                    .foregroundStyle(.white)
                    .frame(width: height * 0.55, height: height * 0.55)
                    .rotationEffect(.degrees(-18))
                    .keyframeAnimator(initialValue: CGFloat.zero, repeating: repeats) { content, value in
                        let approach = showsStaticPose ? 1 : value
                        content.offset(x: -width * 0.025 * approach, y: -height * 0.22 * approach)
                    } keyframes: { _ in
                        CubicKeyframe(1, duration: 0.7)
                        LinearKeyframe(1, duration: 0.65)
                        CubicKeyframe(0, duration: 0.7)
                        LinearKeyframe(0, duration: 0.9)
                    }
                    .position(x: width * 0.7, y: height * 0.73)
            }
        }
        .aspectRatio(1.3, contentMode: .fit)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hold the top of your phone near the breathalyzer's NFC tag.")
            Text(Self.instruction)
                .font(.system(.subheadline, design: .rounded)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }
}
