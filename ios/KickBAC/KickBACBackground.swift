import SwiftUI

/// Slowly shifting light behind Home and the dark Welcome screen.
struct KickBACBackground: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var appearedAt = Date.now
    @State private var isVisible = false

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1.0 / 30,
                                    paused: reduceMotion || !isVisible || scenePhase != .active)) { timeline in
                Rectangle()
                    .fill(.white)
                    .colorEffect(ShaderLibrary.kickBACLight(
                        .float2(Float(geometry.size.width), Float(geometry.size.height)),
                        .float(reduceMotion ? 0 : Float(timeline.date.timeIntervalSince(appearedAt))),
                        .float(contrast == .increased ? 0.35 : 1)
                    ))
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }
}
