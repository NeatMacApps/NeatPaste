import SwiftUI

struct HistoryPanelView: View {
    @Bindable var model: HistoryPanelModel
    @FocusState private var searchFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            HStack(spacing: 0) {
                historyList
                    .frame(minWidth: 240)
                Divider()
                previewPane
                    .frame(minWidth: 220)
            }
            if model.needsAccessibilityPrompt {
                accessibilityBanner
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(8)
        .focusEffectDisabled()
        .onAppear {
            searchFocused = true
        }
        .onChange(of: model.query) { _, _ in
            Task { await model.applyFilter() }
        }
    }

    private var searchBar: some View {
        TextField(String(localized: "panel.search.placeholder"), text: $model.query)
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .focused($searchFocused)
            .focusEffectDisabled()
            .background(Color(nsColor: .textBackgroundColor))
    }

    private var historyList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.visibleItems) { item in
                        HistoryRowView(
                            item: item,
                            isSelected: item.id == model.selectedID
                        )
                        .frame(height: AppPreferences.rowHeight)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            model.selectedID = item.id
                        }
                        .id(item.id)
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: model.selectedID) { _, id in
                if let id {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private var previewPane: some View {
        Group {
            if let item = model.selectedItem {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if item.hasImage {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.secondary.opacity(0.18))
                                .frame(width: 96, height: 96)
                                .overlay {
                                    Image(systemName: "photo")
                                        .font(.title)
                                        .foregroundStyle(.secondary)
                                }
                                .accessibilityLabel(String(localized: "panel.image.placeholder"))
                        }
                        Text(item.plainText)
                            .font(.system(size: 13))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(14)
                }
            } else {
                Text(String(localized: "panel.preview.empty"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var accessibilityBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "panel.accessibility.title"))
                .font(.headline)
            Text(String(localized: "panel.copiedOnly"))
                .font(.callout)
            Text(String(localized: "panel.accessibility.body"))
                .font(.callout)
                .foregroundStyle(.secondary)
            Button(String(localized: "panel.accessibility.openSettings")) {
                AccessibilityPermission.promptIfNeeded()
                AccessibilityPermission.openSystemSettings()
            }
            .buttonStyle(.borderedProminent)
            .focusEffectDisabled()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct HistoryRowView: View {
    let item: HistoryItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            if item.hasImage {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 28, height: 28)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
            } else {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            Text(item.plainText)
                .font(.system(size: 13))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.35), lineWidth: 1.5)
            }
        }
        .padding(.horizontal, 6)
        .focusEffectDisabled()
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
