import SwiftUI

struct CommunityView: View {
    @StateObject private var store = CommunityStore()

    var body: some View {
        List {
            Section("Students") {
                ForEach(CommunityStudent.featured) { student in
                    HStack(spacing: 12) {
                        NavigationLink {
                            CommunityChatView(student: student)
                                .environmentObject(store)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: student.avatarSymbol)
                                    .foregroundStyle(VerbaTheme.green)
                                    .frame(width: 34, height: 34)
                                    .background(VerbaTheme.cream)
                                    .clipShape(Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(student.name)
                                        if student.isOnline {
                                            Circle()
                                                .fill(.green)
                                                .frame(width: 8, height: 8)
                                        }
                                    }
                                    Text("\(student.grade) • \(student.bio)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Spacer()
                        Button(store.isFollowing(student) ? "Following" : "Follow") {
                            store.toggleFollow(student)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .navigationTitle("Community")
    }
}

private struct CommunityChatView: View {
    let student: CommunityStudent

    @EnvironmentObject private var store: CommunityStore
    @State private var composer = ""

    var body: some View {
        VStack {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(store.messages(for: student)) { message in
                        HStack {
                            if message.isCurrentUser { Spacer() }
                            Text(message.body)
                                .padding(12)
                                .background(message.isCurrentUser ? VerbaTheme.green.opacity(0.15) : VerbaTheme.cream)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            if !message.isCurrentUser { Spacer() }
                        }
                    }
                }
                .padding()
            }

            HStack {
                TextField("DM \(student.name)", text: $composer)
                    .textFieldStyle(.roundedBorder)
                Button("Send") {
                    store.send(composer, to: student)
                    composer = ""
                }
                .disabled(composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .navigationTitle(student.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
