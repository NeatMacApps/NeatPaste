import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class HistoryPanelModel {
    var query = ""
    var visibleItems: [HistoryItem] = []
    var selectedID: HistoryItem.ID?
    var needsAccessibilityPrompt = false

    var onHide: (() -> Void)?
    var onPasteOutcome: ((PasteOutcome) -> Void)?

    private let history: any HistoryServing
    private var allItems: [HistoryItem] = []

    var selectedItem: HistoryItem? {
        visibleItems.first { $0.id == selectedID } ?? visibleItems.first
    }

    init(history: any HistoryServing) {
        self.history = history
    }

    func reload() async {
        query = ""
        needsAccessibilityPrompt = false
        allItems = await history.items()
        visibleItems = allItems
        selectedID = visibleItems.first?.id
    }

    func applyFilter() async {
        visibleItems = await history.search(query)
        if let selectedID, visibleItems.contains(where: { $0.id == selectedID }) {
            return
        }
        self.selectedID = visibleItems.first?.id
    }

    func moveSelection(_ delta: Int) {
        guard !visibleItems.isEmpty else { return }
        let current = visibleItems.firstIndex { $0.id == selectedID } ?? 0
        let next = min(max(current + delta, 0), visibleItems.count - 1)
        selectedID = visibleItems[next].id
    }

    func dismiss() {
        onHide?()
    }

    func confirmPaste() async {
        guard let item = selectedItem else { return }
        let trusted = AccessibilityPermission.isTrusted
        if trusted {
            onHide?()
        }
        let outcome = await PasteEngine.paste(record: item)
        onPasteOutcome?(outcome)
        if outcome == .copiedOnly {
            needsAccessibilityPrompt = true
        }
    }
}
