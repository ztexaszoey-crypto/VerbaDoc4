//
//  VerbaDoc4App.swift
//  VerbaDoc4
//
//  Created by Zoey Ding on 4/17/26.
//

import SwiftUI
import Combine

@main
struct VerbaDoc4App: App {
    @AppStorage(AppState.hasOnboardedKey) private var hasOnboarded = false
    @StateObject private var appState = AppState()
    @StateObject private var streakManager = StreakManager()
    @StateObject private var xpManager = XPManager()

    var body: some Scene {
        WindowGroup {
            ZStack {
                if !hasOnboarded {
                    OnboardingView()
                        .onAppear {
                            print("DEBUG: hasOnboarded = \(hasOnboarded)")
                        }
                } else {
                    RootTabView()
                }
            }
            .environmentObject(appState)
            .environmentObject(streakManager)
            .environmentObject(xpManager)
        }
    }
}
