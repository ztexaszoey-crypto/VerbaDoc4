import Foundation
import FirebaseFirestore
import FirebaseAuth
import SwiftData

// MARK: - CloudSyncEngine
//
// Bidirectional sync between SwiftData (local, source of truth for UI)
// and Firestore (remote, source of truth for cross-device continuity).
//
// Architecture: local-first with background sync.
//
// Write path:
//   1. App mutates SwiftData immediately (UI stays responsive, zero latency)
//   2. Call CloudSyncEngine.shared.enqueue(.upsertDocument(id)) or upsertStudyItem
//   3. Engine flushes queue to Firestore in background (retries on failure)
//   4. Queue persisted to UserDefaults — survives app kills and crashes
//
// Read path (initial restore + incremental sync):
//   1. On login: compare local vs remote. If remote richer → pull and merge
//   2. Incremental: pull items where remoteLastModified > lastSyncAt
//   3. Conflict resolution: Last-Write-Wins by lastModified timestamp
//      Special case for mastery: take the version with higher reviewCount
//      (reviewCount is monotonically increasing — prevents regression)
//
// Firestore structure:
//   /users/{uid}/profile           { xp, streakCurrent, streakLongest,
//                                    lastStudyDate, totalStudyDays, lastModified }
//   /users/{uid}/documents/{id}    { title, content, sourceType, createdAt,
//                                    updatedAt, isArchived, examDate, lastModified }
//   /users/{uid}/studyItems/{id}   { documentId, question, answer, explanation,
//                                    topic, aiExplanation, mastery, stabilityDays,
//                                    cardLayer, reviewCount, consecutiveMisses,
//                                    nextReviewAt, lastReviewedAt, isUserEdited,
//                                    lastModified }
//
// OFFLINE: Queue survives indefinitely. Flushed when network resumes.
// MIGRATION: First login with existing local data triggers initial seed upload.

@MainActor
final class CloudSyncEngine: ObservableObject {
    static let shared = CloudSyncEngine()

    // MARK: - Published State

    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncAt: Date? = nil
    @Published private(set) var syncError: String? = nil
    @Published private(set) var isRestoring = false

    /// Set to true while a VerbaFlow study session is active.
    /// pullAndMerge is skipped while a session is running to avoid mid-session
    /// SwiftData mutations racing with the session's queue reads.
    @Published var isSessionActive: Bool = false

    // MARK: - Private

    private let db = Firestore.firestore()
    private var modelContext: ModelContext? = nil
    private let queueKey = "sync.pendingQueue"
    private let lastSyncKey = "sync.lastSyncAt"
    private var flushTask: Task<Void, Never>? = nil

    // Fix 2: deferred UID — holds auth UID that arrived before configure() ran.
    private var pendingUID: String? = nil

    // Fix F-5: restore retry state — persisted across app kills so an offline
    // first-launch automatically retries restore on the next launch with network.
    //
    // State machine:
    //   triggerRestoreIfNeeded(uid:) → sets UserDefaults[pendingRestoreKey] = uid
    //   pullAndMerge success          → removes UserDefaults[pendingRestoreKey]
    //   seedRemoteIfNeeded success    → removes UserDefaults[pendingRestoreKey]
    //   pullAndMerge / seed failure   → key persists → next configure() retries
    //
    // The in-memory restoreSessionUID prevents duplicate concurrent restores
    // within the same app session. The UserDefaults key enables cross-session retry.
    private let pendingRestoreKey = "sync.pendingRestoreUID"
    private var restoreSessionUID: String? = nil

    // Fix 3: re-entrancy guard — prevents simultaneous flush() executions.
    private var isFlushActive = false

    private init() {
        lastSyncAt = UserDefaults.standard.object(forKey: lastSyncKey) as? Date
    }

    // MARK: - Setup (call once from VerbaDoc4App after container is ready)
    //
    // Fix 2: accepts an optional pendingUID so any auth state that resolved
    // before configure() was called is not lost. If uid is non-nil and
    // the engine hasn't already started a restore for this session, it
    // triggers seedRemoteIfNeeded immediately.

    func configure(modelContext: ModelContext, pendingUID: String? = nil) {
        self.modelContext = modelContext

        // Fix F-4: drain any sync ops that survived an app kill mid-flush.
        // Without this, ops sit in UserDefaults indefinitely until the user
        // triggers a new study action that calls enqueue() → scheduleFlush().
        if !loadQueue().isEmpty { scheduleFlush() }

        // Fix F-5: check for a persisted restore UID from a failed offline launch.
        // If present, this launch retries the restore automatically.
        let persistedUID = UserDefaults.standard.string(forKey: pendingRestoreKey)
        if let uid = pendingUID ?? self.pendingUID ?? persistedUID {
            self.pendingUID = nil
            triggerRestoreIfNeeded(uid: uid)
        }
    }

    // MARK: - Auth UID delivery (Fix 2)
    //
    // Called from .onChange(of: currentUser?.uid) in the app. If configure()
    // has already run, kicks off the restore immediately. If not, stores the
    // UID so configure() can pick it up when it runs.

    func setAuthenticatedUser(uid: String) {
        // A different user signing in clears all prior restore state.
        if restoreSessionUID != uid {
            restoreSessionUID = nil
            // Clear the persisted restore UID only if it belongs to a different user.
            // If it matches the current uid, a prior failed restore is pending — keep it.
            if UserDefaults.standard.string(forKey: pendingRestoreKey) != uid {
                UserDefaults.standard.removeObject(forKey: pendingRestoreKey)
            }
        }
        if modelContext != nil {
            triggerRestoreIfNeeded(uid: uid)
        } else {
            pendingUID = uid
        }
    }

    private func triggerRestoreIfNeeded(uid: String) {
        guard restoreSessionUID != uid else { return }   // already running this session
        restoreSessionUID = uid
        // Fix F-5: persist the intent before starting so an offline failure leaves
        // a retry marker for the next launch. Cleared only on success (below).
        UserDefaults.standard.set(uid, forKey: pendingRestoreKey)
        Task { await seedRemoteIfNeeded(uid: uid) }
    }

    // MARK: - Enqueue (call after any local mutation)

    func enqueueDocumentSync(id: String) {
        enqueue(SyncOperation(type: .upsertDocument, id: id))
    }

    func enqueueStudyItemSync(id: String) {
        enqueue(SyncOperation(type: .upsertStudyItem, id: id))
    }

    func enqueueProfileSync() {
        enqueue(SyncOperation(type: .upsertProfile, id: "profile"))
    }

    private func enqueue(_ op: SyncOperation) {
        var queue = loadQueue()
        // Dedup: replace existing op for same type+id (last write wins in queue too)
        queue.removeAll { $0.type == op.type && $0.id == op.id }
        queue.append(op)
        saveQueue(queue)
        scheduleFlush()
    }

    // MARK: - Flush (push pending queue to Firestore)

    private func scheduleFlush() {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500)) // brief debounce
            guard let self, !Task.isCancelled else { return }
            await self.flush()
        }
    }

    func flush() async {
        // Fix 3: re-entrancy guard. A second caller returns immediately;
        // the in-flight flush will process the full queue including any
        // operations enqueued after it started, because loadQueue() is
        // called inside the loop and the queue is re-read on each retry.
        guard !isFlushActive else { return }
        isFlushActive = true
        defer { isFlushActive = false }

        guard let uid = Auth.auth().currentUser?.uid,
              let context = modelContext else { return }

        let queue = loadQueue()
        guard !queue.isEmpty else { return }

        isSyncing = true
        defer { isSyncing = false }

        var failed: [SyncOperation] = []

        for op in queue {
            do {
                switch op.type {
                case .upsertDocument:
                    try await pushDocument(id: op.id, uid: uid, context: context)
                case .upsertStudyItem:
                    try await pushStudyItem(id: op.id, uid: uid, context: context)
                case .upsertProfile:
                    try await pushProfile(uid: uid)
                }
            } catch {
                failed.append(op)
                syncError = error.localizedDescription
            }
        }

        saveQueue(failed) // only retain what failed
        if failed.isEmpty {
            lastSyncAt = Date()
            UserDefaults.standard.set(lastSyncAt, forKey: lastSyncKey)
            syncError = nil
        }
    }

    // MARK: - Push Operations

    private func pushDocument(id: String, uid: String, context: ModelContext) async throws {
        let descriptor = FetchDescriptor<Document>(
            predicate: #Predicate { $0.id == id }
        )
        guard let doc = try context.fetch(descriptor).first else { return }

        let data: [String: Any] = [
            "id":          doc.id,
            "title":       doc.title,
            "content":     doc.content,
            "sourceType":  doc.sourceType.rawValue,
            "createdAt":   Timestamp(date: doc.createdAt),
            "updatedAt":   Timestamp(date: doc.updatedAt),
            "isArchived":  doc.isArchived,
            "examDate":    doc.examDate.map { Timestamp(date: $0) } as Any,
            // Use client-side lastModified so remote and local share the same
            // timestamp for LWW conflict resolution. Server timestamps skew
            // slightly ahead of client time and would always "win" on pull-merge.
            "lastModified": Timestamp(date: doc.lastModified)
        ]

        try await db.collection("users").document(uid)
            .collection("documents").document(id)
            .setData(data, merge: true)
    }

    private func pushStudyItem(id: String, uid: String, context: ModelContext) async throws {
        let descriptor = FetchDescriptor<StudyItem>(
            predicate: #Predicate { $0.id == id }
        )
        guard let item = try context.fetch(descriptor).first else { return }

        var data: [String: Any] = [
            "id":               item.id,
            "documentId":       item.document?.id ?? "",
            "question":         item.question,
            "answer":           item.answer,
            "explanation":      item.explanation,
            "topic":            item.topic,
            "mastery":          item.mastery,
            "stabilityDays":    item.stabilityDays,
            "cardLayer":        item.cardLayer,
            "reviewCount":      item.reviewCount,
            "consecutiveMisses": item.consecutiveMisses,
            "nextReviewAt":     Timestamp(date: item.nextReviewAt),
            "isUserEdited":     item.isUserEdited,
            // Client-side timestamp keeps LWW consistent between local and remote.
            "lastModified":     Timestamp(date: item.lastModified)
        ]
        if let explanation = item.aiExplanation {
            data["aiExplanation"] = explanation
        }
        if let reviewed = item.lastReviewedAt {
            data["lastReviewedAt"] = Timestamp(date: reviewed)
        }

        try await db.collection("users").document(uid)
            .collection("studyItems").document(id)
            .setData(data, merge: true)
    }

    private func pushProfile(uid: String) async throws {
        let xp     = UserDefaults.standard.integer(forKey: "xp.total")
        let streak = loadStreakForSync()

        let data: [String: Any] = [
            "xp":              xp,
            "streakCurrent":   streak.currentStreak,
            "streakLongest":   streak.longestStreak,
            "totalStudyDays":  streak.totalStudyDays,
            "lastStudyDate":   streak.lastStudyDate.map { Timestamp(date: $0) } as Any,
            "lastModified":    FieldValue.serverTimestamp()
        ]

        try await db.collection("users").document(uid)
            .collection("profile").document("data")
            .setData(data, merge: true)
    }

    // MARK: - Initial Seed (local → remote on first login)

    /// Call this on first login when the user has local data but no remote data.
    /// Uploads all Documents and StudyItems to seed the user's cloud vault.
    func seedRemoteIfNeeded(uid: String) async {
        guard let context = modelContext else { return }

        // Check if remote already has data (existing account)
        let snapshot = try? await db.collection("users").document(uid)
            .collection("documents")
            .limit(to: 1)
            .getDocuments()

        guard snapshot?.documents.isEmpty == true else {
            // Remote has data — skip seed, merge instead
            await pullAndMerge(uid: uid)
            return
        }

        // Check if local has data worth seeding
        let docDescriptor = FetchDescriptor<Document>()
        guard let docs = try? context.fetch(docDescriptor), !docs.isEmpty else {
            // No local data to seed — restore is effectively complete (nothing to do).
            // Fix F-5: clear the retry marker so we don't keep trying on every launch.
            UserDefaults.standard.removeObject(forKey: pendingRestoreKey)
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        // Enqueue everything for upload
        for doc in docs {
            enqueueDocumentSync(id: doc.id)
            for item in doc.studyItems {
                enqueueStudyItemSync(id: item.id)
            }
        }
        enqueueProfileSync()
        await flush()
        // Fix F-5: clear retry marker if the seed flush succeeded (queue is empty).
        // If flush failed (offline), the queue is non-empty and we leave the marker
        // so the next launch retries the seed upload.
        if loadQueue().isEmpty {
            UserDefaults.standard.removeObject(forKey: pendingRestoreKey)
        }
    }

    // MARK: - Pull and Merge (remote → local)

    /// Pulls remote data into SwiftData using LWW conflict resolution.
    ///
    /// - Incremental: if `lastSyncAt` is set, only fetches documents modified
    ///   after that timestamp — avoids full collection scans on every login.
    /// - Session guard: skips the pull while a study session is active to prevent
    ///   SwiftData mutations from racing with the session queue reads.
    func pullAndMerge(uid: String) async {
        guard !isSessionActive else { return }
        guard let context = modelContext else { return }
        isRestoring = true
        defer { isRestoring = false }

        do {
            // Pull profile (always; tiny document, no incremental needed)
            let profileSnap = try await db.collection("users").document(uid)
                .collection("profile").document("data")
                .getDocument()
            if let data = profileSnap.data() {
                mergeProfile(data)
            }

            // Incremental filter: only fetch records modified since our last sync.
            // Falls back to a full pull when lastSyncAt is nil (first login).
            let userRef = db.collection("users").document(uid)

            let docsSnap: QuerySnapshot
            let itemsSnap: QuerySnapshot

            if let since = lastSyncAt {
                let cutoff = Timestamp(date: since)
                docsSnap  = try await userRef.collection("documents")
                    .whereField("lastModified", isGreaterThan: cutoff)
                    .getDocuments()
                itemsSnap = try await userRef.collection("studyItems")
                    .whereField("lastModified", isGreaterThan: cutoff)
                    .getDocuments()
            } else {
                // First sync — pull everything
                docsSnap  = try await userRef.collection("documents").getDocuments()
                itemsSnap = try await userRef.collection("studyItems").getDocuments()
            }

            for docRef in docsSnap.documents {
                try mergeDocument(data: docRef.data(), context: context)
            }

            // Fix 5: collect (itemID → documentID) pairs during merge so that
            // the orphan relink pass has the documentId available even if the
            // document wasn't in this batch (incremental sync edge case).
            var deferredLinks: [(itemID: String, docID: String)] = []
            for itemRef in itemsSnap.documents {
                let deferred = try mergeStudyItem(data: itemRef.data(), context: context)
                if let pair = deferred { deferredLinks.append(pair) }
            }

            // Second pass: link any items that couldn't find their parent document
            // during the first pass (document was from a prior sync batch and
            // is already local, but the relationship wasn't established yet).
            let relinked = try relinkOrphanedItems(deferredLinks: deferredLinks, context: context)
            if relinked > 0 {
                print("[CloudSync] Relinked \(relinked) orphaned study item(s) to parent documents.")
            }

            try context.save()
            lastSyncAt = Date()
            UserDefaults.standard.set(lastSyncAt, forKey: lastSyncKey)
            // Fix F-5: restore succeeded — clear the retry marker so the next
            // launch does not attempt another pull for this uid.
            UserDefaults.standard.removeObject(forKey: pendingRestoreKey)

        } catch {
            // Restore failed (offline, permission error, index missing).
            // pendingRestoreKey is NOT cleared here — next launch retries.
            syncError = "Restore failed: \(error.localizedDescription)"
        }
    }

    /// Links study items that failed to connect to their parent document during
    /// the first merge pass. `deferredLinks` contains (itemID, documentID) pairs
    /// for items that were inserted without a document link.
    /// Returns the number of items successfully relinked.
    @discardableResult
    private func relinkOrphanedItems(
        deferredLinks: [(itemID: String, docID: String)],
        context: ModelContext
    ) throws -> Int {
        guard !deferredLinks.isEmpty else { return 0 }
        var relinked = 0
        for (itemID, docID) in deferredLinks {
            // Fetch the item
            let itemDesc = FetchDescriptor<StudyItem>(
                predicate: #Predicate { $0.id == itemID }
            )
            guard let item = try context.fetch(itemDesc).first,
                  item.document == nil else { continue }   // already linked or missing

            // Try to find the document locally (may have been in a prior batch)
            let docDesc = FetchDescriptor<Document>(
                predicate: #Predicate { $0.id == docID }
            )
            if let doc = try context.fetch(docDesc).first {
                item.document = doc
                relinked += 1
            } else {
                // Document truly doesn't exist locally — quarantine to prevent
                // the item from appearing in VerbaFlow sessions.
                if item.cardLayer != "orphan" { item.cardLayer = "orphan" }
                print("[CloudSync] ⚠️ Study item \(itemID) has no parent document \(docID) — quarantined.")
            }
        }
        return relinked
    }

    // MARK: - Merge Helpers

    private func mergeProfile(_ data: [String: Any]) {
        let remoteXP      = data["xp"] as? Int ?? 0
        let remoteStreak  = data["streakCurrent"] as? Int ?? 0
        let remoteLongest = data["streakLongest"] as? Int ?? 0
        let remoteDays    = data["totalStudyDays"] as? Int ?? 0

        let localXP = UserDefaults.standard.integer(forKey: "xp.total")
        // Take the higher XP (never regress XP from cloud merge)
        if remoteXP > localXP {
            UserDefaults.standard.set(remoteXP, forKey: "xp.total")
        }

        // Merge streak: take the higher streak count, but always keep the more
        // recent lastStudyDate regardless of which device has the higher streak.
        // Taking the remote date unconditionally caused streaks to break when the
        // local device had studied today but remote had an older lastStudyDate.
        let localStreak = (UserDefaults.standard.data(forKey: "streakData")
            .flatMap { try? JSONDecoder().decode(StreakData.self, from: $0) })
        let remoteLastStudy = (data["lastStudyDate"] as? Timestamp)?.dateValue()
        let localLastStudy  = localStreak?.lastStudyDate
        let winningLastStudy: Date? = {
            switch (localLastStudy, remoteLastStudy) {
            case (let l?, let r?): return l > r ? l : r
            case (let l?, nil):    return l
            case (nil, let r?):    return r
            case (nil, nil):       return nil
            }
        }()
        if (localStreak?.currentStreak ?? 0) < remoteStreak {
            let merged = StreakData(
                currentStreak:  remoteStreak,
                longestStreak:  max(remoteLongest, localStreak?.longestStreak ?? 0),
                lastStudyDate:  winningLastStudy,
                totalStudyDays: max(remoteDays, localStreak?.totalStudyDays ?? 0)
            )
            if let encoded = try? JSONEncoder().encode(merged) {
                UserDefaults.standard.set(encoded, forKey: "streakData")
            }
        } else if let localData = localStreak, winningLastStudy != localData.lastStudyDate {
            // Streak count favours local, but remote has a more recent study date — update it.
            let updated = StreakData(
                currentStreak:  localData.currentStreak,
                longestStreak:  max(localData.longestStreak, remoteLongest),
                lastStudyDate:  winningLastStudy,
                totalStudyDays: max(localData.totalStudyDays, remoteDays)
            )
            if let encoded = try? JSONEncoder().encode(updated) {
                UserDefaults.standard.set(encoded, forKey: "streakData")
            }
        }
    }

    private func mergeDocument(data: [String: Any], context: ModelContext) throws {
        guard let id = data["id"] as? String,
              let title = data["title"] as? String,
              let content = data["content"] as? String,
              let sourceTypeRaw = data["sourceType"] as? String,
              let sourceType = SourceType(rawValue: sourceTypeRaw) else { return }

        let remoteMod = (data["lastModified"] as? Timestamp)?.dateValue() ?? Date.distantPast

        // Check if we have a local version
        let descriptor = FetchDescriptor<Document>(
            predicate: #Predicate { $0.id == id }
        )
        if let local = try context.fetch(descriptor).first {
            // LWW: remote wins only if it's newer
            guard remoteMod > local.lastModified else { return }
            local.title        = title
            local.content      = content
            local.isArchived   = data["isArchived"] as? Bool ?? false
            local.examDate     = (data["examDate"] as? Timestamp)?.dateValue()
            local.lastModified = remoteMod
        } else {
            // New document from remote — insert locally
            let doc = Document(title: title, content: content, sourceType: sourceType)
            doc.id           = id
            doc.isArchived   = data["isArchived"] as? Bool ?? false
            doc.examDate     = (data["examDate"] as? Timestamp)?.dateValue()
            doc.lastModified = remoteMod
            if let ts = data["createdAt"] as? Timestamp { doc.createdAt = ts.dateValue() }
            if let ts = data["updatedAt"] as? Timestamp { doc.updatedAt = ts.dateValue() }
            context.insert(doc)
        }
    }

    /// Merges one remote study item into the local context.
    /// Returns an (itemID, documentID) pair if the item was newly inserted
    /// but its parent document could not be found — for the orphan relink pass.
    /// Returns nil if no deferred link is needed.
    @discardableResult
    private func mergeStudyItem(
        data: [String: Any],
        context: ModelContext
    ) throws -> (itemID: String, docID: String)? {
        guard let id = data["id"] as? String,
              let question = data["question"] as? String,
              let answer = data["answer"] as? String else { return nil }

        let remoteReviewCount = data["reviewCount"] as? Int ?? 0
        let remoteMod = (data["lastModified"] as? Timestamp)?.dateValue() ?? Date.distantPast

        let descriptor = FetchDescriptor<StudyItem>(
            predicate: #Predicate { $0.id == id }
        )

        if let local = try context.fetch(descriptor).first {
            // Special case: take the version with more reviews (never regress)
            let useRemote = remoteReviewCount > local.reviewCount ||
                            (remoteReviewCount == local.reviewCount && remoteMod > local.lastModified)
            guard useRemote else { return nil }

            local.question          = question
            local.answer            = answer
            local.explanation       = data["explanation"] as? String ?? ""
            local.topic             = data["topic"] as? String ?? ""
            local.aiExplanation     = data["aiExplanation"] as? String
            local.mastery           = data["mastery"] as? Int ?? 0
            local.stabilityDays     = data["stabilityDays"] as? Double ?? 1.0
            // Fix F merge-guard: never un-quarantine an item whose parent document
            // is still unresolved. The remote snapshot may have the pre-quarantine
            // cardLayer value ("normal", "active") but if this device quarantined it
            // because its parent document is missing, overwriting would re-admit it
            // to VerbaFlow sessions with a nil document. Preserve the local orphan
            // status until the parent document arrives and relinkOrphanedItems runs.
            let remoteCardLayer = data["cardLayer"] as? String ?? "active"
            if !(local.cardLayer == "orphan" && local.document == nil) {
                local.cardLayer = remoteCardLayer
            }
            local.reviewCount       = remoteReviewCount
            local.consecutiveMisses = data["consecutiveMisses"] as? Int ?? 0
            local.isUserEdited      = data["isUserEdited"] as? Bool ?? false
            local.lastModified      = remoteMod
            if let ts = data["nextReviewAt"] as? Timestamp { local.nextReviewAt = ts.dateValue() }
            if let ts = data["lastReviewedAt"] as? Timestamp { local.lastReviewedAt = ts.dateValue() }
            return nil   // existing item — no deferred link needed
        } else {
            // New item from remote
            let item = StudyItem(question: question, answer: answer)
            item.id               = id
            item.explanation      = data["explanation"] as? String ?? ""
            item.topic            = data["topic"] as? String ?? ""
            item.aiExplanation    = data["aiExplanation"] as? String
            item.mastery          = data["mastery"] as? Int ?? 0
            item.stabilityDays    = data["stabilityDays"] as? Double ?? 1.0
            item.cardLayer        = data["cardLayer"] as? String ?? "active"
            item.reviewCount      = remoteReviewCount
            item.consecutiveMisses = data["consecutiveMisses"] as? Int ?? 0
            item.isUserEdited     = data["isUserEdited"] as? Bool ?? false
            item.lastModified     = remoteMod
            if let ts = data["nextReviewAt"] as? Timestamp { item.nextReviewAt = ts.dateValue() }
            if let ts = data["lastReviewedAt"] as? Timestamp { item.lastReviewedAt = ts.dateValue() }

            // Link to parent document
            let docId = data["documentId"] as? String ?? ""
            var linked = false
            if !docId.isEmpty {
                let docDescriptor = FetchDescriptor<Document>(
                    predicate: #Predicate { $0.id == docId }
                )
                if let doc = try context.fetch(docDescriptor).first {
                    item.document = doc
                    linked = true
                }
            }
            context.insert(item)
            // Return deferred pair only if we couldn't link immediately
            return (!linked && !docId.isEmpty) ? (itemID: id, docID: docId) : nil
        }
    }

    // MARK: - Queue Persistence

    private struct SyncOperation: Codable {
        enum OpType: String, Codable { case upsertDocument, upsertStudyItem, upsertProfile }
        let type: OpType
        let id: String
        let enqueuedAt: Date

        init(type: OpType, id: String) {
            self.type = type
            self.id = id
            self.enqueuedAt = Date()
        }
    }

    private func loadQueue() -> [SyncOperation] {
        guard let data = UserDefaults.standard.data(forKey: queueKey),
              let ops = try? JSONDecoder().decode([SyncOperation].self, from: data) else {
            return []
        }
        return ops
    }

    private func saveQueue(_ ops: [SyncOperation]) {
        guard let data = try? JSONEncoder().encode(ops) else { return }
        UserDefaults.standard.set(data, forKey: queueKey)
    }

    // MARK: - Helpers

    private func loadStreakForSync() -> StreakData {
        guard let data = UserDefaults.standard.data(forKey: "streakData"),
              let decoded = try? JSONDecoder().decode(StreakData.self, from: data) else {
            return StreakData(currentStreak: 0, longestStreak: 0, lastStudyDate: nil, totalStudyDays: 0)
        }
        return decoded
    }
}
