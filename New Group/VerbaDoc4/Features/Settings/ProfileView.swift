import SwiftUI
import SwiftData

struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var streakManager: StreakManager
    @Query(sort: \Document.createdAt, order: .reverse) private var documents: [Document]
    @Query(sort: \StudyItem.createdAt, order: .reverse) private var allItems: [StudyItem]

    @Environment(\.dismiss) private var dismiss

    @State private var profile = UserProfile()
    @State private var isEditingProfile = false
    @State private var showPaywall = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                profileHeaderSection
                statsSection
                studyGoalSection
                premiumSection
                subjectsSection
                dangerSection
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $isEditingProfile) {
                editProfileSheet
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .confirmationDialog(
                "Delete All Data",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Everything", role: .destructive) {
                    resetProfile()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will clear your profile data and reset your streak. This cannot be undone.")
            }
            .onAppear { loadProfile() }
        }
    }

    // MARK: - Profile Header

    private var profileHeaderSection: some View {
        Section {
            HStack(spacing: 16) {
                Image(systemName: "face.smiling.fill")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(VerbaTheme.green)

                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.name.isEmpty ? "Student" : profile.name)
                        .font(.title2.bold())
                    Text(profile.age > 0 ? "Age \(profile.age)" : "Tap Edit to set up your profile")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Edit") {
                    isEditingProfile = true
                    HapticManager.impact()
                }
                .font(.subheadline.bold())
                .foregroundStyle(VerbaTheme.green)
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Stats

    private var statsSection: some View {
        Section("Stats") {
            HStack {
                statItem(
                    icon: "flame.fill",
                    value: "\(streakManager.currentStreak)",
                    label: "Day Streak",
                    color: .orange
                )
                Divider()
                statItem(
                    icon: "rectangle.stack.fill",
                    value: "\(allItems.count)",
                    label: "Total Cards",
                    color: VerbaTheme.green
                )
                Divider()
                statItem(
                    icon: "books.vertical.fill",
                    value: "\(documents.count)",
                    label: "Documents",
                    color: .blue
                )
            }
            .frame(height: 80)
        }
    }

    private func statItem(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.title3.bold())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Study Goal

    private var studyGoalSection: some View {
        Section("Daily Study Goal") {
            HStack {
                Label("Cards per day", systemImage: "target")
                Spacer()
                Text("\(profile.studyGoal)")
                    .foregroundStyle(.secondary)
            }

            Stepper(
                value: $profile.studyGoal,
                in: 5...100,
                step: 5
            ) {
                Text("Goal: \(profile.studyGoal) cards")
                    .foregroundStyle(.secondary)
            }
            .onChange(of: profile.studyGoal) { _, _ in
                saveProfile()
                HapticManager.selection()
            }
        }
    }

    // MARK: - Premium

    private var premiumSection: some View {
        Section("Membership") {
            HStack {
                Label(appState.hasPremium ? "Premium Member" : "Free Tier", systemImage: appState.hasPremium ? "crown.fill" : "person.fill")
                    .foregroundStyle(appState.hasPremium ? VerbaTheme.xpGold : .primary)
                Spacer()
                if appState.hasPremium {
                    Text("Active")
                        .font(.caption.bold())
                        .foregroundStyle(VerbaTheme.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(VerbaTheme.green.opacity(0.15))
                        .clipShape(Capsule())
                }
            }

            if !appState.hasPremium {
                Button {
                    showPaywall = true
                    HapticManager.impact()
                } label: {
                    Label("Upgrade to Premium", systemImage: "sparkles")
                        .foregroundStyle(VerbaTheme.green)
                }
            }
        }
    }

    // MARK: - Subjects

    private var subjectsSection: some View {
        Section("Favourite Subjects") {
            if profile.preferredSubjects.isEmpty {
                Text("No subjects selected. Tap to add some.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(profile.preferredSubjects) { subject in
                    Label(subject.name, systemImage: subject.icon)
                        .foregroundStyle(subject.color)
                }
            }

            NavigationLink {
                subjectPickerView
            } label: {
                Label("Edit Subjects", systemImage: "pencil")
            }
        }
    }

    private var subjectPickerView: some View {
        List(Subject.all) { subject in
            let isSelected = profile.preferredSubjects.contains(subject)
            Button {
                toggleSubject(subject)
                HapticManager.selection()
            } label: {
                HStack {
                    Label(subject.name, systemImage: subject.icon)
                        .foregroundStyle(subject.color)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark")
                            .foregroundStyle(VerbaTheme.green)
                    }
                }
            }
            .foregroundStyle(.primary)
        }
        .navigationTitle("Subjects")
    }

    // MARK: - Danger Zone

    private var dangerSection: some View {
        Section("Data") {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Reset Profile Data", systemImage: "trash")
            }
        }
    }

    // MARK: - Edit Profile Sheet

    private var editProfileSheet: some View {
        NavigationStack {
            Form {
                Section("About You") {
                    HStack {
                        Text("Name")
                        Spacer()
                        TextField("Your name", text: $profile.name)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        Text("Age")
                        Spacer()
                        TextField("Age", text: Binding(
                            get: { String(profile.age > 0 ? profile.age : 0) },
                            set: { profile.age = Int($0) ?? 0 }
                        ))
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isEditingProfile = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveProfile()
                        isEditingProfile = false
                        HapticManager.success()
                    }
                    .fontWeight(.bold)
                }
            }
        }
    }

    // MARK: - Persistence

    private func loadProfile() {
        let defaults = UserDefaults.standard
        profile.name = defaults.string(forKey: "profile.name") ?? ""
        profile.age = defaults.integer(forKey: "profile.age")
        profile.studyGoal = defaults.integer(forKey: "profile.studyGoal")
        if profile.studyGoal == 0 { profile.studyGoal = 20 }
    }

    private func saveProfile() {
        let defaults = UserDefaults.standard
        defaults.set(profile.name, forKey: "profile.name")
        defaults.set(profile.age, forKey: "profile.age")
        defaults.set(profile.studyGoal, forKey: "profile.studyGoal")
    }

    private func toggleSubject(_ subject: Subject) {
        if profile.preferredSubjects.contains(subject) {
            profile.preferredSubjects.removeAll { $0 == subject }
        } else {
            profile.preferredSubjects.append(subject)
        }
        saveProfile()
    }

    private func resetProfile() {
        profile = UserProfile()
        streakManager.reset()
        saveProfile()
        HapticManager.success()
    }
}
