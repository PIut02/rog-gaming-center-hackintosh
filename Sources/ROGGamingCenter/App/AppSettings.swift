import Foundation
import AuraCore

enum ROGKeyAction: String, CaseIterable, Identifiable, Codable {
    case toggleMainWindow = "toggle_main_window"
    case cyclePresets = "cycle_presets"
    case toggleBacklight = "toggle_backlight_power"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .toggleMainWindow: return "Show or hide ROG Gaming Center"
        case .cyclePresets: return "Switch to the next lighting preset"
        case .toggleBacklight: return "Turn the backlight on or off"
        }
    }
}

/// Keyboard backlight hardware style. `.automatic` follows the detected HID
/// product ID; the explicit choices exist because the GA401's N-KEY controller
/// PID is shared with other 2021 laptops.
enum KeyboardLEDStyle: String, CaseIterable, Identifiable, Codable {
    case automatic
    case white
    case rgb

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .white: return "White (GA401)"
        case .rgb: return "RGB (multi-zone)"
        }
    }
}

struct AppSettings: Codable, Equatable {
    var lighting: LightingState = .default
    var customPresets: [AuraPreset] = []
    var displayProfile: DisplayProfile = .standard
    var keyboardLEDStyle: KeyboardLEDStyle = .automatic
    var keepRunningInMenuBar = true
    var showDockIcon = true
    var rogKeyEnabled = true
    var rogKeyAction: ROGKeyAction = .toggleMainWindow
    var globalShortcutsEnabled = true
    var showBrightnessHUD = true

    init() {}

    // Tolerates missing keys so new settings can be added without a migration.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        lighting = try c.decodeIfPresent(LightingState.self, forKey: .lighting) ?? d.lighting
        customPresets = try c.decodeIfPresent([AuraPreset].self, forKey: .customPresets) ?? d.customPresets
        displayProfile = try c.decodeIfPresent(DisplayProfile.self, forKey: .displayProfile) ?? d.displayProfile
        keyboardLEDStyle = (try? c.decodeIfPresent(KeyboardLEDStyle.self, forKey: .keyboardLEDStyle)) ?? d.keyboardLEDStyle
        keepRunningInMenuBar = try c.decodeIfPresent(Bool.self, forKey: .keepRunningInMenuBar) ?? d.keepRunningInMenuBar
        showDockIcon = try c.decodeIfPresent(Bool.self, forKey: .showDockIcon) ?? d.showDockIcon
        rogKeyEnabled = try c.decodeIfPresent(Bool.self, forKey: .rogKeyEnabled) ?? d.rogKeyEnabled
        rogKeyAction = (try? c.decodeIfPresent(ROGKeyAction.self, forKey: .rogKeyAction)) ?? d.rogKeyAction
        globalShortcutsEnabled = try c.decodeIfPresent(Bool.self, forKey: .globalShortcutsEnabled) ?? d.globalShortcutsEnabled
        showBrightnessHUD = try c.decodeIfPresent(Bool.self, forKey: .showBrightnessHUD) ?? d.showBrightnessHUD
    }
}

/// Persists `AppSettings` as one JSON value. Writes are debounced so dragging a
/// color picker does not hammer UserDefaults.
@MainActor
final class SettingsStore {
    private static let key = "AppSettings.v1"
    private let defaults: UserDefaults
    private var pendingSave: DispatchWorkItem?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AppSettings {
        if let data = defaults.data(forKey: Self.key),
           let settings = try? JSONDecoder().decode(AppSettings.self, from: data) {
            return settings
        }
        let migrated = migrateLegacy()
        saveNow(migrated)
        return migrated
    }

    func save(_ settings: AppSettings) {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow(settings) }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func flush(_ settings: AppSettings) {
        pendingSave?.cancel()
        saveNow(settings)
    }

    private func saveNow(_ settings: AppSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Self.key)
        }
    }

    /// Reads the pre-2.0 `Aura_*` keys once.
    private func migrateLegacy() -> AppSettings {
        var s = AppSettings()
        let d = defaults

        if let data = d.data(forKey: "Aura_CustomPresets"),
           let presets = try? JSONDecoder().decode([AuraPreset].self, from: data) {
            s.customPresets = presets
        }
        if d.object(forKey: "Aura_CloseToTray") != nil { s.keepRunningInMenuBar = d.bool(forKey: "Aura_CloseToTray") }
        if d.object(forKey: "Aura_ROGKeyEnabled") != nil { s.rogKeyEnabled = d.bool(forKey: "Aura_ROGKeyEnabled") }
        if let raw = d.string(forKey: "Aura_ROGKeyAction") {
            s.rogKeyAction = ROGKeyAction(rawValue: raw) ?? .toggleMainWindow // "toggle_popover" maps to the window
        }

        var lighting = LightingState.default
        if d.object(forKey: "Aura_Brightness") != nil {
            let level = d.integer(forKey: "Aura_Brightness")
            if level > 0 { lighting.brightness = min(3, level) }
        }
        if d.object(forKey: "Aura_IsPoweredOn") != nil { lighting.isOn = d.bool(forKey: "Aura_IsPoweredOn") }
        let zones = (d.stringArray(forKey: "Aura_ZoneColors") ?? []).compactMap(AuraColor.init(hex:))
        let speed = AuraSpeed(rawValue: d.integer(forKey: "Aura_Speed")) ?? .medium

        if let id = d.string(forKey: "Aura_ActivePresetId") {
            if let preset = (AuraPreset.builtInPresets + s.customPresets).first(where: { $0.id == id }) {
                lighting.mode = preset.mode
                lighting.presetID = preset.id
            } else if id == "custom_4zone", zones.count == 4 {
                lighting.mode = .multiStatic(zones)
                lighting.presetID = nil
            } else if id == "custom_single", let first = zones.first {
                lighting.mode = .singleStatic(first)
                lighting.presetID = nil
            }
        }
        lighting.mode = lighting.mode.withSpeed(speed)
        s.lighting = lighting
        return s
    }
}
