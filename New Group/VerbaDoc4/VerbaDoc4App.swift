//
//  VerbaDoc4App.swift
//  VerbaDoc4
//
//  Created by Zoey Ding on 4/17/26.
//

import SwiftUI
import SwiftData

@main
struct VerbaDoc4App: App {
    @AppStorage(AppState.hasOnboardedKey) private var hasOnboarded = false
    @State private var showSplash = true
    @StateObject private var appState = AppState()
    @StateObject private var streakManager = StreakManager()
    @StateObject private var xpManager = XPManager()
    let modelContainer: ModelContainer

    init() {
        let schema = Schema([StudyItem.self, Document.self])
        do {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, allowsSave: true)
            self.modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            self.modelContainer = try! ModelContainer(for: schema, configurations: [fallback])
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if showSplash {
                    SplashView(isFinished: $showSplash)
                        .transition(.opacity)
                } else if !hasOnboarded {
                    OnboardingView()
                        .transition(.opacity)
                } else {
                    RootTabView()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: showSplash)
            .animation(.easeInOut(duration: 0.3), value: hasOnboarded)
            .environmentObject(appState)
            .environmentObject(streakManager)
            .environmentObject(xpManager)
            .modelContainer(modelContainer)
        }
    }
}
