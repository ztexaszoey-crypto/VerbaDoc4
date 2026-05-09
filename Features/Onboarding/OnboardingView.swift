import SwiftUI

struct OnboardingView: View {
    @AppStorage(AppState.hasOnboardedKey) private var hasOnboarded = false
    @State private var stepIndex = 0

    private var step: VerbaCharacter { VerbaCharacter.onboardingSteps[stepIndex] }

    var body: some View {
        ZStack {
            LinearGradient(colors: [VerbaTheme.ink, VerbaTheme.background], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: step.symbol)
                    .font(.system(size: 66, weight: .bold))
                    .foregroundStyle(VerbaTheme.green)

                Text(step.name)
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)

                Text(step.message)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 24)

                Spacer()

                HStack(spacing: 10) {
                    ForEach(VerbaCharacter.onboardingSteps.indices, id: \.self) { index in
                        Circle()
                            .fill(index == stepIndex ? VerbaTheme.green : .white.opacity(0.3))
                            .frame(width: 10, height: 10)
                    }
                }

                Button(stepIndex == VerbaCharacter.onboardingSteps.count - 1 ? "Get Started" : "Next") {
                    print("DEBUG: Button tapped, stepIndex=\(stepIndex), total=\(VerbaCharacter.onboardingSteps.count)")
                    HapticManager.impact()
                    if stepIndex == VerbaCharacter.onboardingSteps.count - 1 {
                        print("DEBUG: Setting hasOnboarded = true")
                        hasOnboarded = true
                        HapticManager.success()
                    } else {
                        stepIndex += 1
                        HapticManager.selection()
                    }
                }
                .buttonStyle(VerbaButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 36)
            }
        }
    }
}
