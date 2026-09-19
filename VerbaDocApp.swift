import SwiftUI
import SwiftData
import RevenueCat
import Combine

@main
struct VerbaDocApp: App {

    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var auth         = AuthService.shared
    @StateObject private var purchases    = PurchaseService.shared
    @StateObject private var gate         = ProGate.shared
    @StateObject private var xpManager    = XPManager()
    @StateObject private var streakManager = StreakManager()
    @StateObject private var tabRouter    = TabRouter()
    @StateObject private var syncEngine   = CloudSyncEngine()

    init() {
        // Configure RevenueCat before any purchase calls.
        // The delegate is set inside configure() so real-time updates work immediately.
        PurchaseService.configure()
    }

    var sharedModelContainer: ModelContainer = {
        // Misconception Mapping (DESIGN.md §3): Concept / StudentConcept /
        // Misconception are the knowledge-graph models. MasteryEngine is a
        // pure enum (no @Model) and needs no schema registration.
        let schema = Schema([
            Document.self,
            StudyItem.self,
            Topic.self,
            UserProgress.self,
            StudySessionEntity.self,
            ReviewRecord.self,
            Achievement.self,
            Concept.self,
            StudentConcept.self,
            Misconception.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Persistent store failed (I/O error, transient disk condition).
            // Do NOT delete the store files — they may contain user data and the
            // next launch may succeed (e.g. if the failure was a transient full-disk).
            // Fall back to in-memory for this session only so the app remains usable.
            print("[VerbaDoc] ModelContainer init failed (\(error)). Using in-memory store for this session.")
            let fallbackConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            if let fallback = try? ModelContainer(for: schema, configurations: [fallbackConfig]) {
                return fallback
            }
            // Absolute last-resort: even in-memory cannot initialise (e.g.
            // schema-level corruption). Surface a hard assertionFailure so
            // TestFlight captures the failure instead of a crash-loop that
            // prevents App Review.
            assertionFailure("[VerbaDoc] Cannot create in-memory ModelContainer: \(error). App is non-functional for this session.")
            NSLog("[VerbaDoc] FATAL_MODEL_CONTAINER_INIT_FAILED: %@. Constructing placeholder; SwiftData calls in this session will no-op.", String(describing: error))
            let placeholder = (try? ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
            ))
            return placeholder ?? { fatalError("[VerbaDoc] Placeholder ModelContainer construction failed.") }()
        }
    }()

    var body: some Scene {
        WindowGroup {
            Group {
                if !hasSeenOnboarding {
                    SplashView()
                } else if !auth.isSignedIn {
                    SignInView()
                } else {
                    RootTabView()
                        .task {
                            // Refresh auth token if near expiry
                            await AuthService.shared.refreshIfNeeded()
                            // Refresh entitlement every foreground — handles renewals,
                            // cancellations, and billing recovery automatically.
                            await purchases.refreshEntitlement()
                        }
                }
            }
            .environmentObject(auth)
            .environmentObject(purchases)
            .environmentObject(gate)
            .environmentObject(xpManager)
            .environmentObject(streakManager)
            .environmentObject(tabRouter)
            .environmentObject(syncEngine)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    AnalyticsManager.shared.track(.appOpen)
                    NotificationManager.shared.refreshPermissionStatus()
                    Task { await AuthService.shared.refreshIfNeeded() }
                }
            }
            .onChange(of: auth.currentUser) { _, user in
                Task {
                    if let user {
                        await purchases.logIn(userID: user.id)
                    } else {
                        await purchases.logOut()
                    }
                }
            }
        }
        .modelContainer(sharedModelContainer)
    }
}
