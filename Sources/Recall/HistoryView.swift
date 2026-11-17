import RecallCore
import SwiftUI

/// The panel: a search field, what has been copied with the most recent first, and a status line.
///
/// The search field keeps the keyboard the whole time. Whether keys act on the query or on
/// the selected clip is decided by `list.focus`, which the panel consults for every key.
struct HistoryView: View {
    let model: AppModel
    @Bindable var list: HistoryList
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField(L("history.search.placeholder"), text: $list.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($searchFocused)
                    .accessibilityLabel(L("history.search.label"))
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 11)

            Divider()

            if model.clipboardAccess != .allowed {
                AccessNotice(model: model)
                Divider()
            }

            let results = list.results
            if results.isEmpty {
                EmptyHistory(model: model, isSearching: !list.query.isEmpty)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(results) { clip in
                                ClipRow(
                                    clip: clip,
                                    isSelected: clip.id == list.selectedID,
                                    listHasFocus: list.focus == .list,
                                    model: model)
                                    .id(clip.id)
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: list.selectedID) { _, id in
                        if let id { proxy.scrollTo(id) }
                    }
                }
            }

            Divider()
            StatusLine(model: model, hasSelection: list.selectedID != nil, listHasFocus: list.focus == .list)
        }
        .ignoresSafeArea()
        .onAppear { searchFocused = true }
    }
}

private struct ClipRow: View {
    let clip: Clip
    let isSelected: Bool
    let listHasFocus: Bool
    let model: AppModel
    @State private var isHovered = false

    private var isEmphasized: Bool { isSelected && listHasFocus }
    private var preview: String { ClipPreview.line(for: clip.text) }
    private var time: String { TimeLabel.string(for: clip.used, now: Date()) }
    private var kindName: String { clip.kind == .link ? L("history.kind.link") : L("history.kind.text") }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: clip.kind == .link ? "link" : "text.alignleft")
                .font(.system(size: 12))
                .frame(width: 16)
                .foregroundStyle(isEmphasized ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
                .help(kindName)

            Text(preview)
                .lineLimit(1)
                .truncationMode(clip.kind == .link ? .middle : .tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isSelected || isHovered {
                Button {
                    model.delete(clip)
                } label: {
                    Image(systemName: "trash").frame(width: 14)
                }
                .help(L("history.row.delete"))
                .accessibilityLabel(L("history.row.delete"))
            }

            Text(time)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(isEmphasized ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(isEmphasized ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(background, in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { model.copy(clip) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kindName): \(preview), \(time)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.copy(clip) }
        .accessibilityAction(named: L("history.row.copy")) { model.copy(clip) }
        .accessibilityAction(named: L("history.row.delete")) { model.delete(clip) }
    }

    private var background: AnyShapeStyle {
        if isEmphasized { return AnyShapeStyle(Color.accentColor) }
        if isSelected { return AnyShapeStyle(.primary.opacity(0.1)) }
        if isHovered { return AnyShapeStyle(.primary.opacity(0.05)) }
        return AnyShapeStyle(.clear)
    }
}

/// Shown instead of the list when there is nothing to show.
private struct EmptyHistory: View {
    let model: AppModel
    let isSearching: Bool

    var body: some View {
        VStack(spacing: 6) {
            if isSearching {
                Text(L("history.noMatches"))
                    .foregroundStyle(.secondary)
            } else {
                Text(L("history.empty.title"))
                    .font(.headline)
                Text(model.isPaused ? L("history.empty.paused") : L("history.empty.hint", model.shortcutDisplay))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Tells the user that macOS is not letting Recall read the clipboard, and where to change that.
private struct AccessNotice: View {
    let model: AppModel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(model.clipboardAccess == .denied ? L("access.denied") : L("access.asks"))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(L("access.open")) { model.openClipboardSettings() }
                .controlSize(.small)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
}

/// The line at the bottom: what state Recall is in, and what the keys do.
private struct StatusLine: View {
    let model: AppModel
    let hasSelection: Bool
    let listHasFocus: Bool

    var body: some View {
        HStack(spacing: 12) {
            if model.isPaused {
                Label(L("status.paused"), systemImage: "pause.circle")
                Button(L("status.resume")) { model.setPaused(false) }
                    .buttonStyle(.link)
            } else if model.store.saveFailed {
                Label(L("status.saveFailed"), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .help(L("status.saveFailed.help"))
            }
            Spacer()
            if hasSelection {
                if listHasFocus {
                    Text(L("status.hint.delete"))
                }
                Text(L("status.hint.copy"))
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .frame(height: 30)
    }
}
