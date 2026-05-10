import SwiftUI
import SwiftData

@Observable
class StreakManager {
    var currentStreak: Int = 0
    var longestStreak: Int = 0
    var lastStudyDate: Date?
    var totalStudyDays: Int = 0
    var todayStudied: Bool = false
    
    init() {
        loadStreakData()
    }
    
    // MARK: - Streak Management
    
    func recordStudySession() {
        let today = Calendar.current.startOfDay(for: Date())
        let lastDate = lastStudyDate.map { Calendar.current.startOfDay(for: $0) }
        
        if lastDate == today {
            // Already studied today
            return
        }
        
        if let lastDate = lastDate, Calendar.current.dateComponents([.day], from: lastDate, to: today).day == 1 {
            // Streak continues
            currentStreak += 1
        } else if lastDate == nil || Calendar.current.dateComponents([.day], from: lastDate!, to: today).day! > 1 {
            // Streak broken or first time
            currentStreak = 1
        }
        
        lastStudyDate = Date()
        totalStudyDays += 1
        todayStudied = true
        
        if currentStreak > longestStreak {
            longestStreak = currentStreak
        }
        
        saveStreakData()
    }
    
    // MARK: - Persistence
    
    private func loadStreakData() {
        if let data = UserDefaults.standard.data(forKey: "streakData"),
           let decoded = try? JSONDecoder().decode(StreakData.self, from: data) {
            currentStreak = decoded.currentStreak
            longestStreak = decoded.longestStreak
            lastStudyDate = decoded.lastStudyDate
            totalStudyDays = decoded.totalStudyDays
        }
    }
    
    private func saveStreakData() {
        let data = StreakData(
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            lastStudyDate: lastStudyDate,
            totalStudyDays: totalStudyDays
        )
        if let encoded = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(encoded, forKey: "streakData")
        }
    }
}

struct StreakData: Codable {
    let currentStreak: Int
    let longestStreak: Int
    let lastStudyDate: Date?
    let totalStudyDays: Int
}
