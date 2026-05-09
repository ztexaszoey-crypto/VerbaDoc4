import SwiftUI

struct SplashView: View {
    private let splashDuration: TimeInterval = 1.2

    @Binding var isFinished: Bool
    @State private var scale: CGFloat = 0.85

    var body: some View {
        ZStack {
            LinearGradient(colors: [VerbaTheme.ink, VerbaTheme.background], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Image(systemName: "text.book.closed.fill")
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(VerbaTheme.green)
                    .scaleEffect(scale)

                Text("VerbaDoc4")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)

                Text("AI study, simplified")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.75)) {
                scale = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + splashDuration) {
                isFinished = true
            }
        }
    }
}
