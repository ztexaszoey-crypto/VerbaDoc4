import SwiftUI
import SwiftData
import Combine

struct RootTabView: View {
    enum Tab { case today, library, practice, settings }
    @State private var selected: Tab = .today
    @Query private var allStudyItems: [StudyItem]
    @EnvironmentObject private var xpManager: XPManager
    @EnvironmentObject private var streakManager: StreakManager

    private var dueItems: [StudyItem] {
        let now = Date()
        return allStudyItems.filter { $0.nextReviewAt <= now }
    }

    var body: some View {
        TabView(selection: $selected) {
            TodayView()
                .tabItem { Label("Today", systemImage: "calendar.circle.fill") }
                .tag(Tab.today)
                .badge(dueItems.isEmpty ? 0 : dueItems.count)

            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical.fill") }
                .tag(Tab.library)

            PracticeView()
                .tabItem { Label("Practice", systemImage: "rectangle.stack.fill") }
                .tag(Tab.practice)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(Tab.settings)
        }
        .tint(VerbaTheme.green)
        .onAppear {
            xpManager.awardDailyLoginIfNeeded()
            streakManager.markStudyCompleted()
        }
    }
}
