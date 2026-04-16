import Foundation
import Combine

final class HistoryStore: ObservableObject {
    @Published private(set) var items: [HistoryItem] = []
    private let maxItems = 12

    func record(_ entry: HistoryItem) {
        items.insert(entry, at: 0)

        if items.count > maxItems {
            items.removeLast(items.count - maxItems)
        }
    }
}
