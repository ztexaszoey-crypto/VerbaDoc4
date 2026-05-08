import Combine
import Foundation

@MainActor
final class CommunityStore: ObservableObject {
    @Published private(set) var followedIDs: Set<String> = []
    @Published private(set) var threads: [String: [CommunityChatMessage]] = [:]

    private let autoReplyDelay: TimeInterval = 0.6
    private let defaults: UserDefaults
    private let followedKey = "community.followed"
    private let threadsKey = "community.threads"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        followedIDs = Set(defaults.stringArray(forKey: followedKey) ?? [])
        if let data = defaults.data(forKey: threadsKey),
           let decoded = try? JSONDecoder().decode([String: [CommunityChatMessage]].self, from: data) {
            threads = decoded
        }
    }

    func isFollowing(_ student: CommunityStudent) -> Bool {
        followedIDs.contains(student.id)
    }

    func toggleFollow(_ student: CommunityStudent) {
        if followedIDs.contains(student.id) {
            followedIDs.remove(student.id)
        } else {
            followedIDs.insert(student.id)
        }
        defaults.set(Array(followedIDs), forKey: followedKey)
    }

    func messages(for student: CommunityStudent) -> [CommunityChatMessage] {
        threads[student.id] ?? [
            CommunityChatMessage(sender: student.name, body: "Hey! Want to swap study tips?", isCurrentUser: false)
        ]
    }

    func send(_ body: String, to student: CommunityStudent) {
        let cleaned = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        var thread = messages(for: student)
        thread.append(CommunityChatMessage(sender: "You", body: cleaned, isCurrentUser: true))
        threads[student.id] = thread
        persist()

        let response = autoReply(to: cleaned, from: student)
        DispatchQueue.main.asyncAfter(deadline: .now() + autoReplyDelay) {
            var updated = self.threads[student.id] ?? thread
            updated.append(CommunityChatMessage(sender: student.name, body: response, isCurrentUser: false))
            self.threads[student.id] = updated
            self.persist()
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(threads) {
            defaults.set(data, forKey: threadsKey)
        }
    }

    private func autoReply(to message: String, from student: CommunityStudent) -> String {
        let lowercased = message.lowercased()
        if lowercased.contains("exam") {
            return "I'm doing a timed review tonight — want to compare weak topics after?"
        }
        if lowercased.contains("help") || lowercased.contains("stuck") {
            return "Try explaining it out loud first, then turn the hardest bit into a flashcard."
        }
        return "Nice! I’m focusing on \(student.bio.lowercased()) today."
    }
}
