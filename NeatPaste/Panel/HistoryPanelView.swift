import AppKit
import SwiftUI

struct HistoryPanelView: View {
    @Bindable var model: HistoryPanelModel
    @State private var searchFocused = false
    @State private var hoveredID: HistoryItem.ID?

    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 0) {
                searchBar
                historyList
            }
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if model.needsAccessibilityPrompt {
                accessibilityBanner
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.001))
        .clipShape(RoundedRectangle(cornerRadius: AppPreferences.panelCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppPreferences.panelCornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.24), lineWidth: 0.8)
        }
        .ignoresSafeArea()
        .focusEffectDisabled()
        .onAppear {
            searchFocused = true
        }
        .onChange(of: model.query) { _, _ in
            Task { await model.applyFilter() }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            PanelSearchField(
                text: $model.query,
                placeholder: String(localized: "panel.search.placeholder"),
                isFocused: $searchFocused
            )

            if !model.query.isEmpty {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .accessibilityLabel(String(localized: "panel.search.clear"))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
    }

    private var historyList: some View {
        Group {
            if model.visibleItems.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clipboard")
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(.tertiary)
                    Text(String(localized: "panel.history.empty"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(model.visibleItems) { item in
                                HistoryRowView(
                                    item: item,
                                    isSelected: item.id == model.selectedID,
                                    isHovered: item.id == hoveredID
                                )
                                .frame(height: AppPreferences.rowHeight)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    Task { await model.handleItemClick(item.id) }
                                }
                                .onHover { hovering in
                                    hoveredID = hovering ? item.id : nil
                                }
                                .id(item.id)
                            }
                        }
                        .padding(6)
                    }
                    // Mac 接鼠标时 `.hidden` 只是建议，系统仍会画出滚动条；契约要求永不显示。
                    .scrollIndicators(.never)
                    .onChange(of: model.selectedID) { _, id in
                        if let id {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var accessibilityBanner: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "panel.copiedOnly"))
                    .font(.system(size: 12, weight: .medium))
                Text(String(localized: "panel.accessibility.title"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(String(localized: "panel.accessibility.openSettings")) {
                AccessibilityPermission.promptIfNeeded()
                AccessibilityPermission.openSystemSettings()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .focusEffectDisabled()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        }
    }
}

private struct HistoryRowView: View {
    let item: HistoryItem
    let isSelected: Bool
    let isHovered: Bool

    var body: some View {
        HStack(spacing: 10) {
            artwork
            VStack(alignment: .leading, spacing: 2) {
                Text(HistoryText.listTitle(plainText: item.plainText, hasImage: item.hasImage))
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                Text(HistoryTime.string(from: item.createdAt))
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(rowFill)
        }
        .focusEffectDisabled()
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(HistoryTime.string(from: item.createdAt))
    }

    private var rowFill: Color {
        if isSelected {
            return Color.accentColor.opacity(0.85)
        }
        if isHovered {
            return Color.primary.opacity(0.06)
        }
        return .clear
    }

    @ViewBuilder
    private var artwork: some View {
        if item.hasImage {
            imageArtwork
        } else if let icon = SourceAppArtwork.icon(bundleID: item.sourceBundleID) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                .frame(width: 28, height: 28)
        }
    }

    @ViewBuilder
    private var imageArtwork: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        if let thumbnail = HistoryThumbnail.image(for: item) {
            Image(nsImage: thumbnail)
                .resizable()
                .interpolation(.medium)
                .scaledToFill()
                .frame(width: HistoryThumbnail.side, height: HistoryThumbnail.side)
                .clipShape(shape)
                .accessibilityLabel(String(localized: "panel.image.placeholder"))
        } else {
            shape
                .fill(isSelected ? Color.white.opacity(0.22) : Color.secondary.opacity(0.18))
                .frame(width: HistoryThumbnail.side, height: HistoryThumbnail.side)
                .overlay {
                    Image(systemName: "photo")
                        .font(.system(size: 12))
                        .foregroundStyle(isSelected ? Color.white : Color.secondary)
                }
                .accessibilityLabel(String(localized: "panel.image.placeholder"))
        }
    }
}

private enum HistoryTime {
    nonisolated(unsafe) static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.dateTimeStyle = .named
        return formatter
    }()

    static func string(from date: Date) -> String {
        formatter.localizedString(for: date, relativeTo: Date())
    }
}

private enum SourceAppArtwork {
    static func icon(bundleID: String?) -> NSImage? {
        guard let bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 28, height: 28)
        return icon
    }
}

private struct PanelSearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    @Binding var isFocused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(frame: .zero)
        field.delegate = context.coordinator
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 14)
        field.placeholderString = placeholder
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        field.cell?.usesSingleLineMode = true
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        nsView.placeholderString = placeholder
        let isComposing = (nsView.currentEditor() as? any NSTextInputClient)?.hasMarkedText() == true
        if !isComposing, nsView.stringValue != text {
            nsView.stringValue = text
        }
        if isFocused,
           nsView.window?.isKeyWindow == true,
           nsView.window?.firstResponder !== nsView.currentEditor() {
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        @Binding var isFocused: Bool

        init(text: Binding<String>, isFocused: Binding<Bool>) {
            _text = text
            _isFocused = isFocused
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text = field.stringValue
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            isFocused = true
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            isFocused = false
        }
    }
}
