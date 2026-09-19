import SwiftUI

struct SplashView: View {
    @State private var opacity: Double = 0
    @State private var showNext = false

    var body: some View {
        if showNext {
            OnboardingView()
        } else {
            ZStack {
                VerbaTheme.bg.ignoresSafeArea()

                VStack(spacing: 8) {
                    Text("verbadoc.")
                        .font(VerbaFont.serif(size: 40))
                        .foregroundStyle(VerbaTheme.ink)

                    Text("zero to mastery.")
                        .font(VerbaFont.syne(.medium, size: 15))
                        .foregroundStyle(VerbaTheme.muted)
                }
                .opacity(opacity)
            }
            .onAppear {
                withAnimation(.easeIn(duration: 0.5)) {
                    opacity = 1
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        showNext = true
                    }
                }
            }
        }
    }
}
