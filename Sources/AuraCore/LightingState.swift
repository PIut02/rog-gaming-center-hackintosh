import Foundation

/// Complete backlight state. Every write sends the whole state, so the
/// latest state is always the correct thing to send (no partial updates).
public struct LightingState: Codable, Equatable, Sendable {
    /// Never `.off`; power is tracked separately so the mode survives turning off.
    public var mode: AuraMode
    /// Hardware brightness 1...3 while on.
    public var brightness: Int
    public var isOn: Bool
    /// Preset the state came from, cleared when the user edits it.
    public var presetID: String?

    public init(mode: AuraMode, brightness: Int, isOn: Bool, presetID: String?) {
        self.mode = mode.isOff ? .singleStatic(.white) : mode
        self.brightness = max(1, min(3, brightness))
        self.isOn = isOn
        self.presetID = presetID
    }

    public static let `default` = LightingState(
        mode: .colorCycle(.medium), brightness: 3, isOn: true, presetID: "color_cycle"
    )

    /// 0 when off, otherwise 1...3.
    public var effectiveBrightness: Int { isOn ? brightness : 0 }

    public var transaction: [[UInt8]] {
        isOn
            ? AuraPacketBuilder.buildModeTransaction(mode: mode, brightness: brightness)
            : AuraPacketBuilder.buildModeTransaction(mode: .off, brightness: 0)
    }

    /// Sets brightness 0...3, where 0 turns the backlight off but keeps the last level.
    public mutating func setLevel(_ level: Int) {
        let clamped = max(0, min(3, level))
        if clamped == 0 {
            isOn = false
        } else {
            isOn = true
            brightness = clamped
        }
    }
}
