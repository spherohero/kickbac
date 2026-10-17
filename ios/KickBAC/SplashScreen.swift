import SwiftUI

struct SplashScreen: View {
    var body: some View {
        ZStack {
            Color("SplashBackground")
                .ignoresSafeArea()

            Image("SplashWordmark")
                .fixedSize()
                .accessibilityLabel("Kick back")
        }
        .preferredColorScheme(.dark)
    }
}

#Preview("Splash") {
    SplashScreen()
}
