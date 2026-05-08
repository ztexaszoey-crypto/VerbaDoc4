import Foundation

enum ChallengeCenter {
    private static let claimedKey = "challenges.claimed"

    static func challenges(
        documents: Int,
        dueCards: Int,
        weakCards: Int,
        streak: Int,
        xp: Int,
        defaults: UserDefaults = .standard
    ) -> [StudyChallenge] {
        let claimed = Set(defaults.stringArray(forKey: claimedKey) ?? [])
        let challenges = [
            StudyChallenge(
                id: "daily-review",
                title: "Daily Review",
                detail: "Study at least 3 due cards today.",
                xpReward: 25,
                isCompleted: dueCards >= 3,
                isClaimed: claimed.contains("daily-review")
            ),
            StudyChallenge(
                id: "library-builder",
                title: "Library Builder",
                detail: "Keep 2 or more documents in your library.",
                xpReward: 20,
                isCompleted: documents >= 2,
                isClaimed: claimed.contains("library-builder")
            ),
            StudyChallenge(
                id: "weak-spotter",
                title: "Weak Spotter",
                detail: "Identify at least one weak card under 60% mastery.",
                xpReward: 30,
                isCompleted: weakCards > 0,
                isClaimed: claimed.contains("weak-spotter")
            ),
            StudyChallenge(
                id: "streak-keeper",
                title: "Streak Keeper",
                detail: "Maintain a 3-day study streak.",
                xpReward: 40,
                isCompleted: streak >= 3,
                isClaimed: claimed.contains("streak-keeper")
            ),
            StudyChallenge(
                id: "xp-riser",
                title: "XP Riser",
                detail: "Reach 100 XP total.",
                xpReward: 35,
                isCompleted: xp >= 100,
                isClaimed: claimed.contains("xp-riser")
            )
        ]

        return challenges
    }

    static func claim(_ challenge: StudyChallenge, defaults: UserDefaults = .standard) {
        var claimed = Set(defaults.stringArray(forKey: claimedKey) ?? [])
        claimed.insert(challenge.id)
        defaults.set(Array(claimed), forKey: claimedKey)
    }
}
