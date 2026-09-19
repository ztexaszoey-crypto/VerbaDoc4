import Foundation
import Combine

// MARK: - CloudSyncEngine
//
// v1 is intentionally a no-op stub. All user data is persisted locally via
// SwiftData (Document + StudyItem models). There is **no** cloud sync in v1:
// reinstalling the app loses all decks and progress unless the user has
// exported a `.verbadeck` backup via DeckExporter.
//
// CloudKit (or Supabase) sync is planned for v2 — at that point we will:
//   • mirror Document + StudyItem records server-side under the user's auth id
//   • trigger `isRestoring = true` on sign-in to pull deltas
//   • register an NSUbiquitousKeyValueStore or use CKSyncEngine
//
// Until then, `isRestoring` defaults to false and never changes, so the
// `restoringState` branch in LibraryView is dormant. The Privacy Manifest
// (PrivacyInfo.xcprivacy) accurately reflects this: it lists email + user
// content sent to Supabase Edge Functions for AI generation, but does NOT
// claim cloud backups.
final class CloudSyncEngine: ObservableObject {
    @Published var isRestoring: Bool = false
    // Future: CloudKit sync (see comment above)
}
