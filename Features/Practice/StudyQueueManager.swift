import Foundation
import Combine

final class StudyQueueManager: ObservableObject {
    @Published private(set) var queue: [StudyItem] = []
    @Published private(set) var currentIndex: Int = 0

    /// True once `load(...)` has populated the queue at least once.
    /// Before load runs, `currentIndex == 0 && queue.count == 0` would
    /// make `isComplete` true and prematurely trip the session-complete
    /// view. Tracking load explicitly avoids that initial-frame race.
    @Published private(set) var didLoad: Bool = false

    var currentItem: StudyItem? {
        queue.indices.contains(currentIndex) ? queue[currentIndex] : nil
    }

    var isComplete: Bool { didLoad && currentIndex >= queue.count }

    var progress: Double {
        queue.isEmpty ? 0 : Double(currentIndex) / Double(queue.count)
    }

    func load(items: [StudyItem], scope: DrillScope) {
        let filtered = scope.filter(items)
        queue = filtered.isEmpty ? items.shuffled() : filtered.shuffled()
        currentIndex = 0
        didLoad = true
    }

    func advance() {
        currentIndex += 1
    }
}
