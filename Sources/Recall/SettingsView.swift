import RecallCore
import SwiftUI

struct SettingsView: View {
    let model: AppModel
    @State private var opensAtLogin = LoginItem.isEnabled
    @State private var loginItemFailed = false
    @State private var isConfirmingClear = false

    var body: some View {
        Form {
            Section {
                LabeledContent(L("settings.shortcut.label")) {
                    ShortcutRecorder(model: model)
                }
                Text(model.shortcutMessage ?? L("settings.shortcut.hint"))
                    .font(.callout)
                    .foregroundStyle(model.shortcutMessage == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                    .fixedSize(horizontal: false, vertical: true)

                Toggle(L("settings.login.label"), isOn: $opensAtLogin)
                    .onChange(of: opensAtLogin) { _, enabled in
                        guard enabled != LoginItem.isEnabled else { return }
                        do {
                            try LoginItem.setEnabled(enabled)
                            loginItemFailed = false
                        } catch {
                            loginItemFailed = true
                            opensAtLogin = LoginItem.isEnabled
                        }
                    }
                if loginItemFailed {
                    Text(L("settings.login.failed"))
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }

            Section(L("settings.history.title")) {
                Picker(L("settings.history.count"), selection: maxCount) {
                    ForEach(Limits.countChoices, id: \.self) { count in
                        Text(L("settings.history.count.value", count)).tag(count)
                    }
                }
                Picker(L("settings.history.images"), selection: maxImageCount) {
                    ForEach(Limits.imageCountChoices, id: \.self) { count in
                        Text(count == 0 ? L("settings.history.images.none") : L("settings.history.count.value", count))
                            .tag(count)
                    }
                }
                Picker(L("settings.history.imageSize"), selection: maxImageMegabytes) {
                    ForEach(Limits.imageMegabyteChoices, id: \.self) { megabytes in
                        Text(L("settings.history.imageSize.value", megabytes)).tag(megabytes)
                    }
                }
                .disabled(!model.limits.collectsImages)
                Picker(L("settings.history.age"), selection: maxAgeDays) {
                    Text(L("settings.history.age.day")).tag(1)
                    Text(L("settings.history.age.week")).tag(7)
                    Text(L("settings.history.age.month")).tag(30)
                    Text(L("settings.history.age.quarter")).tag(90)
                    Text(L("settings.history.age.never")).tag(0)
                }
                Button(L("settings.clear.button"), role: .destructive) {
                    isConfirmingClear = true
                }
                .disabled(!model.store.hasAnythingToClear)
            }

            Section(L("settings.privacy.title")) {
                Toggle(L("settings.privacy.collect"), isOn: collecting)
                if model.clipboardAccess != .allowed {
                    HStack(alignment: .firstTextBaseline) {
                        Text(model.clipboardAccess == .denied ? L("access.denied") : L("access.asks"))
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button(L("access.open")) { model.openClipboardSettings() }
                    }
                }
                Text(L("settings.privacy.what"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L("settings.privacy.where"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .firstTextBaseline) {
                    Text(model.historyFolderDisplay)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(3)
                        .truncationMode(.middle)
                        .accessibilityLabel(L("settings.privacy.folder"))
                        .accessibilityValue(model.historyFolderDisplay)
                    Spacer()
                    Button(L("settings.privacy.reveal")) { model.revealHistoryFolder() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .confirmationDialog(
            L("settings.clear.title"), isPresented: $isConfirmingClear
        ) {
            Button(L("settings.clear.confirm"), role: .destructive) { model.clearHistory() }
            Button(L("settings.clear.cancel"), role: .cancel) {}
        } message: {
            Text(L("settings.clear.message"))
        }
    }

    /// A binding to one of the limits. Changing it applies the new limits at once.
    private func limit<Value>(_ keyPath: WritableKeyPath<Limits, Value>) -> Binding<Value> {
        Binding(
            get: { model.limits[keyPath: keyPath] },
            set: { value in
                var limits = model.limits
                limits[keyPath: keyPath] = value
                model.setLimits(limits)
            })
    }

    private var maxCount: Binding<Int> { limit(\.maxCount) }
    private var maxImageCount: Binding<Int> { limit(\.maxImageCount) }
    private var maxImageMegabytes: Binding<Int> { limit(\.maxImageMegabytes) }

    /// Zero stands for "never".
    private var maxAgeDays: Binding<Int> {
        let days = limit(\.maxAgeDays)
        return Binding(get: { days.wrappedValue ?? 0 }, set: { days.wrappedValue = $0 == 0 ? nil : $0 })
    }

    private var collecting: Binding<Bool> {
        Binding(get: { !model.isPaused }, set: { model.setPaused(!$0) })
    }
}
