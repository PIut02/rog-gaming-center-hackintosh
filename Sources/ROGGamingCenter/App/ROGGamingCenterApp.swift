import SwiftUI
import AuraCore

@main
struct ROGGamingCenterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        Window("ROG Gaming Center", id: "main") {
            RootView()
                .environment(model)
        }
        .defaultSize(width: 980, height: 660)
        .windowResizability(.contentMinSize)
        .commands { AppCommands(model: model) }

        MenuBarExtra {
            MenuBarView()
                .environment(model)
        } label: {
            MenuBarLabel()
                .environment(model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appearanceObservation: NSKeyValueObservation?

    /// The bundle icon is the light one; the Dock shows the dark variant in dark mode.
    private func updateDockIcon() {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        NSApp.applicationIconImage = isDark ? BrandImage.load("app_icon_dark", "png") : nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        updateDockIcon()
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.updateDockIcon() }
        }
        MainActor.assumeIsolated {
            if !AppModel.shared.settings.showDockIcon { NSApp.setActivationPolicy(.accessory) }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        MainActor.assumeIsolated { !AppModel.shared.settings.keepRunningInMenuBar }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            MainActor.assumeIsolated { AppModel.shared.showMainWindow() }
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.shared.prepareForTermination() }
    }
}

@MainActor
struct AppCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        SidebarCommands()

        CommandGroup(before: .sidebar) {
            ForEach(Array(SidebarItem.allCases.enumerated()), id: \.element) { index, item in
                Button(item.title) {
                    model.showMainWindow()
                    model.selection = item
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
            Divider()
        }

        CommandMenu("Lighting") {
            Button(model.lighting.state.isOn ? "Turn Backlight Off" : "Turn Backlight On") {
                model.lighting.toggle()
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])

            Button("Brighter") { model.lighting.stepLevel(by: 1) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            Button("Dimmer") { model.lighting.stepLevel(by: -1) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])

            Divider()

            Button("Next Preset") { model.lighting.cyclePreset(by: 1) }
                .keyboardShortcut("]", modifiers: .command)
            Button("Previous Preset") { model.lighting.cyclePreset(by: -1) }
                .keyboardShortcut("[", modifiers: .command)

            Divider()

            Button("Re-sync Keyboard") { model.lighting.resync() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
        }
    }
}
