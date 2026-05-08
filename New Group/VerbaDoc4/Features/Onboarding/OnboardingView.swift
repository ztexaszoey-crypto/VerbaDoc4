import SwiftUI

struct OnboardingView: View {
    @AppStorage(AppState.hasOnboardedKey) private var hasOnboarded = false
    @AppStorage("profile.name") private var profileName = ""
    @AppStorage("profile.grade") private var profileGrade = ""
    @AppStorage("profile.age") private var profileAge = 0
    @AppStorage("profile.email") private var profileEmail = ""
    @AppStorage("profile.avatar") private var profileAvatar = "books.vertical.fill"
    @AppStorage("notifications.hour") private var reminderHour = 9

    @State private var stepIndex = 0
    @State private var isRequestingNotifications = false

    private var step: VerbaCharacter { VerbaCharacter.onboardingSteps[stepIndex] }
    private let grades = ["Grade 6", "Grade 7", "Grade 8", "Grade 9", "Grade 10", "Grade 11", "Grade 12", "College"]

    var body: some View {
        ZStack {
            LinearGradient(colors: [VerbaTheme.background, VerbaTheme.cream], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer(minLength: 12)
                heroCard
                profileCard
                pager
                actionButtons
            }
            .padding(20)
        }
    }

    private var heroCard: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(VerbaTheme.green.opacity(0.12))
                    .frame(width: 112, height: 112)
                Image(systemName: step.symbol)
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(VerbaTheme.green)
            }

            Text(step.name)
                .font(.largeTitle.bold())
                .foregroundStyle(VerbaTheme.ink)

            Text(step.message)
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(VerbaTheme.muted)
        }
        .padding(24)
        .verbaCard(padding: 0)
    }

    private var profileCard: some View {
        Form {
            Section("Your profile") {
                TextField("Name", text: $profileName)
                Picker("Grade", selection: $profileGrade) {
                    Text("Choose grade").tag("")
                    ForEach(grades, id: \.self) { grade in
                        Text(grade).tag(grade)
                    }
                }
                Stepper("Age: \(max(profileAge, 10))", value: Binding(
                    get: { max(profileAge, 10) },
                    set: { profileAge = $0 }
                ), in: 10...100)
                TextField("Email", text: $profileEmail)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
            }

            Section("Pick an avatar") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(AvatarOption.all) { avatar in
                            Button {
                                profileAvatar = avatar.symbol
                                HapticManager.selection()
                            } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: avatar.symbol)
                                        .font(.title2)
                                        .frame(width: 52, height: 52)
                                        .background(profileAvatar == avatar.symbol ? VerbaTheme.green : VerbaTheme.cream)
                                        .foregroundStyle(profileAvatar == avatar.symbol ? .white : VerbaTheme.green)
                                        .clipShape(Circle())
                                    Text(avatar.name)
                                        .font(.caption2)
                                        .foregroundStyle(VerbaTheme.ink)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }

            Section("Daily reminder") {
                Stepper("Reminder hour: \(displayHour(reminderHour))", value: $reminderHour, in: 6...22)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .frame(maxHeight: 360)
    }

    private var pager: some View {
        HStack(spacing: 10) {
            ForEach(VerbaCharacter.onboardingSteps.indices, id: \.self) { index in
                Capsule()
                    .fill(index == stepIndex ? VerbaTheme.green : VerbaTheme.green.opacity(0.2))
                    .frame(width: index == stepIndex ? 28 : 10, height: 10)
                    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: stepIndex)
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button(stepIndex == VerbaCharacter.onboardingSteps.count - 1 ? "Start Learning" : "Next") {
                advance()
            }
            .buttonStyle(VerbaButtonStyle())
            .disabled(profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || profileGrade.isEmpty || profileEmail.isEmpty)

            if stepIndex > 0 {
                Button("Back") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        stepIndex -= 1
                    }
                }
                .buttonStyle(VerbaSecondaryButtonStyle())
            }
        }
        .padding(.bottom, 12)
    }

    private func advance() {
        HapticManager.impact()
        if stepIndex == VerbaCharacter.onboardingSteps.count - 1 {
            Task {
                await completeOnboarding()
            }
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                stepIndex += 1
            }
        }
    }

    private func completeOnboarding() async {
        guard !isRequestingNotifications else { return }
        isRequestingNotifications = true
        _ = await NotificationManager.shared.requestAuthorization()
        NotificationManager.shared.scheduleDailyReminder(hour: reminderHour)
        hasOnboarded = true
        HapticManager.success()
        isRequestingNotifications = false
    }

    private func displayHour(_ hour: Int) -> String {
        switch hour {
        case 0: return "12 AM"
        case 1..<12: return "\(hour) AM"
        case 12: return "12 PM"
        default: return "\(hour - 12) PM"
        }
    }
}
