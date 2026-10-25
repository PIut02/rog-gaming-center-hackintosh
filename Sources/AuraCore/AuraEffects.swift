import Foundation

// MARK: - Effect Families

/// User-facing effect families. Each maps onto one or more hardware `AuraMode`s.
public enum AuraEffect: String, CaseIterable, Identifiable, Codable, Sendable {
    case staticColor
    case breathing
    case colorCycle
    case rainbow
    case strobe

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .staticColor: return "Static"
        case .breathing: return "Breathing"
        case .colorCycle: return "Color Cycle"
        case .rainbow: return "Rainbow"
        case .strobe: return "Strobe"
        }
    }

    public var symbol: String {
        switch self {
        case .staticColor: return "circle.fill"
        case .breathing: return "wind"
        case .colorCycle: return "arrow.triangle.2.circlepath"
        case .rainbow: return "rainbow"
        case .strobe: return "bolt.fill"
        }
    }

    public var usesSpeed: Bool { self != .staticColor }
}

// MARK: - Color Helpers

extension AuraColor {
    /// Fully saturated color at `hue` (0...1, wraps).
    public static func hue(_ hue: Double) -> AuraColor {
        let h = (hue.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) * 6
        let x = 1 - abs(h.truncatingRemainder(dividingBy: 2) - 1)
        let (r, g, b): (Double, Double, Double)
        switch Int(h) {
        case 0: (r, g, b) = (1, x, 0)
        case 1: (r, g, b) = (x, 1, 0)
        case 2: (r, g, b) = (0, 1, x)
        case 3: (r, g, b) = (0, x, 1)
        case 4: (r, g, b) = (x, 0, 1)
        default: (r, g, b) = (1, 0, x)
        }
        return AuraColor(red: UInt8(r * 255), green: UInt8(g * 255), blue: UInt8(b * 255))
    }

    /// Linear blend toward `other`; `t` is clamped to 0...1.
    public func mixed(with other: AuraColor, _ t: Double) -> AuraColor {
        let t = max(0, min(1, t))
        func lerp(_ a: UInt8, _ b: UInt8) -> UInt8 { UInt8((Double(a) + (Double(b) - Double(a)) * t).rounded()) }
        return AuraColor(red: lerp(red, other.red), green: lerp(green, other.green), blue: lerp(blue, other.blue))
    }
}

// MARK: - Mode Editing

extension AuraMode {
    public static let zoneCount = 4

    public var effect: AuraEffect? {
        switch self {
        case .off: return nil
        case .singleStatic, .multiStatic: return .staticColor
        case .singleBreathing, .multiBreathing: return .breathing
        case .colorCycle: return .colorCycle
        case .rainbow: return .rainbow
        case .strobing: return .strobe
        }
    }

    public var speed: AuraSpeed? {
        switch self {
        case .colorCycle(let s), .rainbow(let s), .singleBreathing(_, _, let s),
             .multiBreathing(_, let s), .strobing(_, let s):
            return s
        case .off, .singleStatic, .multiStatic:
            return nil
        }
    }

    public var usesIndividualZones: Bool {
        if case .multiStatic = self { return true }
        return false
    }

    public var primaryColor: AuraColor? {
        switch self {
        case .singleStatic(let c), .singleBreathing(let c, _, _), .strobing(let c, _): return c
        case .multiStatic(let z), .multiBreathing(let z, _): return z.first
        case .off, .colorCycle, .rainbow: return nil
        }
    }

    public var secondaryColor: AuraColor? {
        if case .singleBreathing(_, let c2, _) = self { return c2 }
        return nil
    }

    /// Four per-zone colors as the user sees them for static modes.
    public var zoneColors: [AuraColor] {
        switch self {
        case .multiStatic(let z), .multiBreathing(let z, _):
            return (0..<Self.zoneCount).map { $0 < z.count ? z[$0] : (z.last ?? .white) }
        default:
            return Array(repeating: primaryColor ?? .white, count: Self.zoneCount)
        }
    }

    public func withSpeed(_ speed: AuraSpeed) -> AuraMode {
        switch self {
        case .colorCycle: return .colorCycle(speed)
        case .rainbow: return .rainbow(speed)
        case .singleBreathing(let a, let b, _): return .singleBreathing(a, b, speed)
        case .multiBreathing(let z, _): return .multiBreathing(z, speed)
        case .strobing(let c, _): return .strobing(c, speed)
        case .off, .singleStatic, .multiStatic: return self
        }
    }

    public func settingPrimary(_ color: AuraColor) -> AuraMode {
        switch self {
        case .singleStatic: return .singleStatic(color)
        case .multiStatic: return .multiStatic(Array(repeating: color, count: Self.zoneCount))
        case .singleBreathing(_, let b, let s): return .singleBreathing(color, b, s)
        case .multiBreathing(_, let s): return .singleBreathing(color, .black, s)
        case .strobing(_, let s): return .strobing(color, s)
        case .off, .colorCycle, .rainbow: return self
        }
    }

    public func settingSecondary(_ color: AuraColor) -> AuraMode {
        if case .singleBreathing(let a, _, let s) = self { return .singleBreathing(a, color, s) }
        return self
    }

    public func settingZone(_ index: Int, to color: AuraColor) -> AuraMode {
        guard (0..<Self.zoneCount).contains(index) else { return self }
        var zones = zoneColors
        zones[index] = color
        return .multiStatic(zones)
    }

    public func settingIndividualZones(_ enabled: Bool) -> AuraMode {
        enabled ? .multiStatic(zoneColors) : .singleStatic(primaryColor ?? .white)
    }

    /// Switches effect family while carrying over colors and speed where possible.
    public func converted(to effect: AuraEffect, defaultSpeed: AuraSpeed = .medium) -> AuraMode {
        let speed = self.speed ?? defaultSpeed
        let primary = primaryColor ?? .rogRed
        switch effect {
        case .staticColor:
            return self.effect == .staticColor ? self : .singleStatic(primary)
        case .breathing:
            return self.effect == .breathing ? self : .singleBreathing(primary, secondaryColor ?? .black, speed)
        case .colorCycle:
            return .colorCycle(speed)
        case .rainbow:
            return .rainbow(speed)
        case .strobe:
            return .strobing(primaryColor ?? .white, speed)
        }
    }
}

// MARK: - Preview Simulation

extension AuraSpeed {
    /// Approximate on-device cycle length, used only for the on-screen preview.
    var previewPeriod: TimeInterval {
        switch self {
        case .slow: return 6
        case .medium: return 3.5
        case .fast: return 1.8
        }
    }
}

extension AuraMode {
    /// Colors for the four zones at time `t`, approximating what the controller animates.
    public func previewColors(at t: TimeInterval) -> [AuraColor] {
        let n = Self.zoneCount
        switch self {
        case .off:
            return Array(repeating: .black, count: n)
        case .singleStatic, .multiStatic:
            return zoneColors
        case .singleBreathing(let a, let b, let s):
            let phase = (1 - cos(2 * .pi * t / (s.previewPeriod * 0.7))) / 2
            return Array(repeating: a.mixed(with: b, phase), count: n)
        case .multiBreathing(_, let s):
            let phase = (1 - cos(2 * .pi * t / (s.previewPeriod * 0.7))) / 2
            return zoneColors.map { $0.mixed(with: .black, phase) }
        case .colorCycle(let s):
            return Array(repeating: .hue(t / s.previewPeriod), count: n)
        case .rainbow(let s):
            return (0..<n).map { .hue(t / s.previewPeriod + Double($0) / Double(n)) }
        case .strobing(let c, let s):
            let on = (t / (s.previewPeriod / 7)).truncatingRemainder(dividingBy: 1) < 0.5
            return Array(repeating: on ? c : .black, count: n)
        }
    }
}
