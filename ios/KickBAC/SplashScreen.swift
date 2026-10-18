import SwiftUI

struct SplashScreen: View {
    var body: some View {
        ZStack {
            Color("SplashBackground")
                .ignoresSafeArea()

            Image("KickBACWordmark")
                .fixedSize()
                .accessibilityLabel("KickBAC")
        }
        .preferredColorScheme(.dark)
    }
}

#Preview("Splash") {
    SplashScreen()
}
