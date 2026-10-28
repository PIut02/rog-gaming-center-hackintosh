import Foundation

// MARK: - Device Profile

/// Lighting capabilities of the connected keyboard controller.
///
/// The GA401 (Zephyrus G14) family drives a **single-zone white** LED chain over
/// the same ITE Aura protocol as RGB models: only the red channel of a packet is
/// meaningful (g-helper zeroes the green/blue bytes for every GA401), and the
/// firmware only renders static, breathing and pulse-style effects.
public struct AuraDeviceProfile: Equatable, Sendable {
    /// White LED chain: green/blue packet channels are forced to zero and
    /// RGB-only effects degrade to static white.
    public var isWhiteKeyboard: Bool
    /// Number of independently addressable zones (1 = single-zone).
    public var zoneCount: Int

    public init(isWhiteKeyboard: Bool, zoneCount: Int) {
        self.isWhiteKeyboard = isWhiteKeyboard
        self.zoneCount = max(1, zoneCount)
    }

    /// Full RGB, four hardware zones (the historic default).
    public static let standardRGB = AuraDeviceProfile(isWhiteKeyboard: false, zoneCount: AuraMode.zoneCount)
    /// GA401 family: single white zone.
    public static let whiteSingleZone = AuraDeviceProfile(isWhiteKeyboard: true, zoneCount: 1)

    /// Effect families this controller can actually render.
    public var supportedEffects: [AuraEffect] {
        isWhiteKeyboard ? [.staticColor, .breathing, .strobe] : AuraEffect.allCases
    }

    /// Best-effort guess from a HID product ID. `0x19B6` is the 2021-era
    /// N-KEY controller used by the GA401 family (shared with some other
    /// 2021 laptops), so this is only a default the user can override in
    /// Settings.
    public static func resolve(productID: Int?) -> AuraDeviceProfile {
        guard let productID, productID != 0 else { return .standardRGB }
        return productID == 0x19B6 ? .whiteSingleZone : .standardRGB
    }
}

// MARK: - White-Keyboard Normalization

extension AuraMode {
    /// Degraded mode for a white single-zone controller: RGB-only effects
    /// collapse to static white, per-zone colors collapse to the primary color.
    public func normalizedForWhiteKeyboard() -> AuraMode {
        switch self {
        case .colorCycle, .rainbow:
            return .singleStatic(.white)
        case .multiStatic(let zones):
            return .singleStatic(zones.first ?? .white)
        case .multiBreathing(let zones, let speed):
            return .singleBreathing(zones.first ?? .white, .black, speed)
        default:
            return self
        }
    }
}
