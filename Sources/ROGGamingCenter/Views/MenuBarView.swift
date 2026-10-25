import SwiftUI
import AuraCore

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    /// The panel itself. It doesn't close on its own after a button press.
    @State private var panel: NSWindow?

    var body: some View {
        let lighting = model.lighting
        let status = ConnectionStatus(model: model)

        VStack(alignment: .leading, spacing: 10) {
            // Only speak up when something needs attention.
            if status.level != .good {
                Button {
                    closePanel()
                    model.showMainWindow()
                    if model.hidAccess != .granted {
                        model.isPermissionSheetPresented = true
                    } else {
                        model.selection = .status
                    }
                } label: {
                    Label(status.title, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(status.color)
                }
                .buttonStyle(.plain)
            }

            // A macOS switch sits right after its label; spell out the row to pin it to the trailing edge.
            HStack {
                Text("Keyboard Light").font(.headline)
                Spacer()
                Toggle("Keyboard Light", isOn: Binding(get: { lighting.state.isOn }, set: { lighting.setOn($0) }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }

            HStack(spacing: 8) {
                Image(systemName: "sun.min").foregroundStyle(.secondary)
                Slider(value: Binding(
                    get: { Double(lighting.state.effectiveBrightness) },
                    set: { lighting.setLevel(Int($0.rounded())) }
                ), in: 0...3, step: 1)
                Image(systemName: "sun.max").foregroundStyle(.secondary)
            }
            .disabled(!lighting.state.isOn)
            .accessibilityLabel("Keyboard brightness")

            Divider()

            LabeledContent("Lighting") {
                Picker("Lighting", selection: Binding(
                    get: { lighting.state.presetID ?? "" },
                    set: { id in lighting.allPresets.first { $0.id == id }.map(lighting.apply) }
                )) {
                    if lighting.activePreset == nil { Text("Custom").tag("") }
                    ForEach(lighting.allPresets) { Text($0.name).tag($0.id) }
                }
                .labelsHidden()
                .fixedSize()
            }
            LabeledContent("Display") {
                Picker("Display", selection: Binding(get: { model.display.profile }, set: { model.display.select($0) })) {
                    ForEach(DisplayProfile.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                MenuRow("Open ROG Gaming Center", shortcut: "O") {
                    closePanel()
                    model.showMainWindow()
                }
                MenuRow("Settings…", shortcut: ",") {
                    closePanel()
                    showSettings()
                }
                MenuRow("Quit ROG Gaming Center", shortcut: "Q") { NSApp.terminate(nil) }
            }
            .padding(.horizontal, -8)
        }
        .padding(14)
        .frame(width: 260)
        .background(WindowAccessor(onWindow: { panel = $0 }, onClose: {}))
    }

    private func closePanel() {
        panel?.close()
    }

    /// `SettingsLink` leaves the window behind other apps when used from the panel,
    /// because clicking the panel doesn't activate the app.
    private func showSettings() {
        NSApp.activate()
        openSettings()
        DispatchQueue.main.async {
            NSApp.windows.first { $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" }?
                .orderFrontRegardless()
        }
    }
}

/// A menu-item-like button that also answers to its ⌘ shortcut while the panel is open.
private struct MenuRow: View {
    let title: String
    let shortcut: Character
    let action: () -> Void

    init(_ title: String, shortcut: Character, action: @escaping () -> Void) {
        self.title = title
        self.shortcut = shortcut
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            MenuRowLabel(title: title, shortcut: shortcut)
        }
        .buttonStyle(MenuRowStyle())
        .keyboardShortcut(KeyEquivalent(Character(shortcut.lowercased())))
    }
}

private struct MenuRowLabel: View {
    let title: String
    let shortcut: Character

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text("⌘\(String(shortcut))").foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

/// Mimics a menu item: plain text that highlights on hover or press.
private struct MenuRowStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 5)
                .fill(isHovered || configuration.isPressed ? Color.primary.opacity(0.1) : .clear))
            .onHover { isHovered = $0 }
    }
}
