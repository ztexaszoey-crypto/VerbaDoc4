import SwiftData
import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var streakManager: StreakManager
    @EnvironmentObject private var xpManager: XPManager
    @Query(sort: [SortDescriptor(\Document.createdAt, order: .reverse)]) private var documents: [Document]
    @Query(sort: [SortDescriptor(\StudyItem.createdAt, order: .reverse)]) private var allItems: [StudyItem]

    @State private var profile = UserProfile()
    @State private var isEditingProfile = false
    @State private var showUnlocks = false
    @State private var showDeleteConfirmation = false

    private let minimumAge = 10

    var body: some View {
        NavigationStack {
            List {
                identityCardSection
                statsSection
                studyGoalSection
                unlocksSection
                subjectsSection
                dangerSection
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $isEditingProfile) {
                editProfileSheet
            }
            .sheet(isPresented: $showUnlocks) {
                UnlocksView()
            }
            .confirmationDialog("Delete All Data", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete Everything", role: .destructive) {
                    resetProfile()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This clears your profile details, study streak, and XP.")
            }
            .onAppear { loadProfile() }
        }
    }

    private var identityCardSection: some View {
        Section {
            IdentityCardView()
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                .listRowBackground(Color.clear)

            HStack {
                profilePill(icon: profile.avatarSymbol, text: profile.name.isEmpty ? "Your name" : profile.name)
                profilePill(icon: "graduationcap.fill", text: profile.grade.isEmpty ? "Grade" : profile.grade)
                profilePill(icon: "envelope.fill", text: profile.email.isEmpty ? "Email" : profile.email)
            }

            Button("Edit profile") {
                isEditingProfile = true
                HapticManager.impact()
            }
            .font(.subheadline.bold())
            .foregroundStyle(VerbaTheme.green)
        }
    }

    private func profilePill(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(VerbaTheme.cream)
            .clipShape(Capsule())
    }

    private var statsSection: some View {
        Section("Stats") {
            HStack {
                statItem(icon: "flame.fill", value: "\(streakManager.currentStreak)", label: "Streak", color: .orange)
                Divider()
                statItem(icon: "bolt.fill", value: "\(xpManager.totalXP)", label: "XP", color: xpManager.currentRank.color)
                Divider()
                statItem(icon: "rectangle.stack.fill", value: "\(allItems.count)", label: "Cards", color: VerbaTheme.green)
                Divider()
                statItem(icon: "books.vertical.fill", value: "\(documents.count)", label: "Docs", color: .blue)
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

    private var studyGoalSection: some View {
        Section("Daily study goal") {
            Stepper(value: $profile.studyGoal, in: 5...100, step: 5) {
                Text("Goal: \(profile.studyGoal) cards")
            }
            .onChange(of: profile.studyGoal) { _, _ in
                saveProfile()
            }
        }
    }

    private var unlocksSection: some View {
        Section("Rewards") {
            Button {
                showUnlocks = true
            } label: {
                Label("View rank badges & unlocks", systemImage: "medal.fill")
                    .foregroundStyle(VerbaTheme.green)
            }
        }
    }

    private var subjectsSection: some View {
        Section("Favourite subjects") {
            if profile.preferredSubjects.isEmpty {
                Text("No subjects selected yet.")
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
                Label("Edit subjects", systemImage: "pencil")
            }
        }
    }

    private var subjectPickerView: some View {
        List(Subject.all) { subject in
            let isSelected = profile.preferredSubjects.contains(subject)
            Button {
                toggleSubject(subject)
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

    private var dangerSection: some View {
        Section("Data") {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Reset profile data", systemImage: "trash")
            }
        }
    }

    private var editProfileSheet: some View {
        NavigationStack {
            Form {
                Section("About you") {
                    TextField("Name", text: $profile.name)
                    TextField("Grade", text: $profile.grade)
                    TextField("Email", text: $profile.email)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                    Stepper("Age: \(max(profile.age, minimumAge))", value: Binding(
                        get: { max(profile.age, minimumAge) },
                        set: { profile.age = $0 }
                    ), in: minimumAge...100)
                }

                Section("Avatar") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72))], spacing: 12) {
                        ForEach(AvatarOption.all) { avatar in
                            Button {
                                profile.avatarSymbol = avatar.symbol
                            } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: avatar.symbol)
                                        .font(.title2)
                                        .frame(width: 52, height: 52)
                                        .background(profile.avatarSymbol == avatar.symbol ? VerbaTheme.green : VerbaTheme.cream)
                                        .foregroundStyle(profile.avatarSymbol == avatar.symbol ? .white : VerbaTheme.green)
                                        .clipShape(Circle())
                                    Text(avatar.name)
                                        .font(.caption2)
                                }
                            }
                            .buttonStyle(.plain)
                        }
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

    private func loadProfile() {
        let defaults = UserDefaults.standard
        profile.name = defaults.string(forKey: "profile.name") ?? ""
        profile.grade = defaults.string(forKey: "profile.grade") ?? ""
        profile.age = defaults.integer(forKey: "profile.age")
        profile.email = defaults.string(forKey: "profile.email") ?? ""
        profile.avatarSymbol = defaults.string(forKey: "profile.avatar") ?? "books.vertical.fill"
        profile.studyGoal = defaults.integer(forKey: "profile.studyGoal")
        if profile.studyGoal == 0 { profile.studyGoal = 20 }

        let savedSubjects = Set(defaults.stringArray(forKey: "profile.subjects") ?? [])
        profile.preferredSubjects = Subject.all.filter { savedSubjects.contains($0.name) }
    }

    private func saveProfile() {
        let defaults = UserDefaults.standard
        defaults.set(profile.name, forKey: "profile.name")
        defaults.set(profile.grade, forKey: "profile.grade")
        defaults.set(profile.age, forKey: "profile.age")
        defaults.set(profile.email, forKey: "profile.email")
        defaults.set(profile.avatarSymbol, forKey: "profile.avatar")
        defaults.set(profile.studyGoal, forKey: "profile.studyGoal")
        defaults.set(profile.preferredSubjects.map(\.name), forKey: "profile.subjects")
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
        xpManager.reset()
        saveProfile()
        HapticManager.success()
    }
}
