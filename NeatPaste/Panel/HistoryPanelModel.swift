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
    /// 鼠标点选触发粘贴时，先挡住双击收尾那一下，避免点穿到下面的窗口。
    var onSuppressClickThrough: (() -> Void)?
    var onPasteOutcome: ((PasteOutcome) -> Void)?
    var onSelectionChange: (() -> Void)?
    private var isPasting = false

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
        onSelectionChange?()
    }

    func applyFilter() async {
        visibleItems = await history.search(query)
        if let selectedID, visibleItems.contains(where: { $0.id == selectedID }) {
            return
        }
        self.selectedID = visibleItems.first?.id
        onSelectionChange?()
    }

    func moveSelection(_ delta: Int) {
        guard !visibleItems.isEmpty else { return }
        let current = visibleItems.firstIndex { $0.id == selectedID } ?? 0
        let next = min(max(current + delta, 0), visibleItems.count - 1)
        select(visibleItems[next].id)
    }

    func select(_ id: HistoryItem.ID) {
        selectedID = id
        onSelectionChange?()
    }

    /// 点未选中的条目只选中；再点已选中的（双击的第二下也落在这里）就粘贴。
    func handleItemClick(_ id: HistoryItem.ID) async {
        switch HistoryItemClick.action(isAlreadySelected: selectedID == id) {
        case .select:
            select(id)
        case .paste:
            await confirmPaste(fromMouse: true)
        }
    }

    func dismiss() {
        onHide?()
    }

    func confirmPaste() async {
        await confirmPaste(fromMouse: false)
    }

    private func confirmPaste(fromMouse: Bool) async {
        guard !isPasting, let item = selectedItem else { return }
        isPasting = true
        defer { isPasting = false }

        let trusted = AccessibilityPermission.isTrusted
        if trusted {
            if fromMouse {
                onSuppressClickThrough?()
            }
            onHide?()
        }
        let outcome = await PasteEngine.paste(record: item)
        onPasteOutcome?(outcome)
        if outcome == .copiedOnly {
            needsAccessibilityPrompt = true
        }
    }
}

enum HistoryItemClick: Equatable, Sendable {
    case select
    case paste

    static func action(isAlreadySelected: Bool) -> HistoryItemClick {
        isAlreadySelected ? .paste : .select
    }
}
