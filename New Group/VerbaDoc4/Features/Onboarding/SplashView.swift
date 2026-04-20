import SwiftUI

struct SplashView: View {
    @Binding var isFinished: Bool

    var body: some View {
        ZStack {
            LinearGradient(colors: [VerbaTheme.dark, VerbaTheme.surf], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(VerbaTheme.green)
                Text("VerbaDoc")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(1.2))
            isFinished = true
        }
    }
}

#Preview {
    SplashView(isFinished: .constant(false))
}
