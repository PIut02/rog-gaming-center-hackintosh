import Foundation
import Observation
import AuraCore
import AuraHID

/// Single owner of the keyboard backlight state. Every change produces a full
/// `LightingState` that is sent to the transport (latest-wins) and reported via
/// `onChange` for persistence.
@MainActor
@Observable
final class LightingController {
    private(set) var state: LightingState
    private(set) var customPresets: [AuraPreset]
    private(set) var lastResult: AuraWriteResult?
    private(set) var lastSuccessfulSync: Date?

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored var onWriteFailure: ((AuraWriteResult) -> Void)?
    @ObservationIgnored private let transport: AuraHIDTransport

    init(state: LightingState, customPresets: [AuraPreset], transport: AuraHIDTransport) {
        self.state = state
        self.customPresets = customPresets
        self.transport = transport
    }

    var allPresets: [AuraPreset] { AuraPreset.builtInPresets + customPresets }

    var activePreset: AuraPreset? {
        state.presetID.flatMap { id in allPresets.first { $0.id == id } }
    }

    // MARK: Power & Brightness

    func setOn(_ on: Bool) {
        update { $0.isOn = on }
    }

    func toggle() { setOn(!state.isOn) }

    /// 0 turns the backlight off, 1...3 sets the hardware level.
    func setLevel(_ level: Int) {
        update { $0.setLevel(level) }
    }

    func stepLevel(by delta: Int) {
        setLevel(state.effectiveBrightness + delta)
    }

    // MARK: Effects

    func setEffect(_ effect: AuraEffect) {
        edit { $0.converted(to: effect) }
    }

    func setSpeed(_ speed: AuraSpeed) {
        edit { $0.withSpeed(speed) }
    }

    func setPrimaryColor(_ color: AuraColor) {
        edit { $0.settingPrimary(color) }
    }

    func setSecondaryColor(_ color: AuraColor) {
        edit { $0.settingSecondary(color) }
    }

    func setZone(_ index: Int, color: AuraColor) {
        edit { $0.settingZone(index, to: color) }
    }

    func setIndividualZones(_ enabled: Bool) {
        edit { $0.settingIndividualZones(enabled) }
    }

    // MARK: Presets

    func apply(_ preset: AuraPreset) {
        update {
            $0.mode = preset.mode
            $0.presetID = preset.id
            $0.isOn = true
        }
    }

    func cyclePreset(by offset: Int) {
        let presets = allPresets
        guard !presets.isEmpty else { return }
        let current = state.presetID.flatMap { id in presets.firstIndex { $0.id == id } }
        let next = current.map { ($0 + offset + presets.count) % presets.count } ?? 0
        apply(presets[next])
    }

    @discardableResult
    func saveCurrentAsPreset(named name: String) -> AuraPreset {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let preset = AuraPreset(
            id: UUID().uuidString,
            name: trimmed.isEmpty ? "Custom \(customPresets.count + 1)" : trimmed,
            icon: "paintpalette.fill",
            mode: state.mode,
            previewColors: state.mode.previewColors(at: 0),
            isCustom: true
        )
        customPresets.append(preset)
        state.presetID = preset.id
        onChange?()
        return preset
    }

    func deletePreset(_ preset: AuraPreset) {
        guard preset.isCustom else { return }
        customPresets.removeAll { $0.id == preset.id }
        if state.presetID == preset.id { state.presetID = nil }
        onChange?()
    }

    func renamePreset(_ preset: AuraPreset, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = customPresets.firstIndex(where: { $0.id == preset.id }) else { return }
        customPresets[i].name = trimmed
        onChange?()
    }

    // MARK: Hardware Sync

    /// Re-sends the full state, e.g. after wake or reconnect when the controller
    /// has fallen back to its firmware default.
    func resync() {
        send()
    }

    // MARK: Private

    /// A user edit of the mode: turns the backlight on and detaches from the preset.
    private func edit(_ transform: (AuraMode) -> AuraMode) {
        update {
            $0.mode = transform($0.mode)
            $0.isOn = true
            $0.presetID = nil
        }
    }

    private func update(_ change: (inout LightingState) -> Void) {
        var next = state
        change(&next)
        guard next != state else { return }
        state = next
        onChange?()
        send()
    }

    private func send() {
        transport.send(state.transaction) { [weak self] result in
            guard let self, result != .superseded else { return }
            self.lastResult = result
            if result.isSuccess {
                self.lastSuccessfulSync = Date()
            } else {
                self.onWriteFailure?(result)
            }
        }
    }
}
