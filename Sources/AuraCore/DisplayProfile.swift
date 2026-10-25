import Foundation

/// GameVisual-style display profiles, applied as gamma transfer tables on top of
/// the display's ColorSync baseline.
public enum DisplayProfile: String, CaseIterable, Codable, Identifiable, Sendable {
    case standard = "standard"
    case vividGaming = "vivid_gaming"
    case eyeCare = "eye_care"
    case cinema = "cinema"
    case fps = "fps"
    case rts = "rts"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .standard: return "Standard"
        case .vividGaming: return "Vivid"
        case .eyeCare: return "Eye Care"
        case .cinema: return "Cinema"
        case .fps: return "FPS"
        case .rts: return "RTS / RPG"
        }
    }

    public var subtitle: String {
        switch self {
        case .standard: return "Your display's calibrated ColorSync profile, unchanged."
        case .vividGaming: return "Lifted midtones and a little more color punch."
        case .eyeCare: return "Warmer whites with reduced blue for long sessions."
        case .cinema: return "Softer contrast with gently lifted shadows."
        case .fps: return "Brightens dark areas so targets in shadow stand out."
        case .rts: return "Stronger midtone lift with warmer, richer color."
        }
    }

    public var symbol: String {
        switch self {
        case .standard: return "display"
        case .vividGaming: return "sparkles"
        case .eyeCare: return "eye"
        case .cinema: return "film"
        case .fps: return "scope"
        case .rts: return "map"
        }
    }

    /// Transforms a baseline gamma table. All channels must have the same length;
    /// outputs stay within 0...1. `.standard` returns the baseline unchanged.
    public func transform(red: [Float], green: [Float], blue: [Float]) -> (red: [Float], green: [Float], blue: [Float]) {
        let n = red.count
        guard n > 1, green.count == n, blue.count == n, self != .standard else { return (red, green, blue) }

        var r = red, g = green, b = blue
        func clamp(_ v: Double) -> Float { Float(max(0, min(1, v))) }

        for i in 0..<n {
            let x = Double(i) / Double(n - 1)
            let br = Double(red[i]), bg = Double(green[i]), bb = Double(blue[i])
            switch self {
            case .standard:
                break
            case .eyeCare:
                r[i] = clamp(br * 1.02); g[i] = clamp(bg * 0.94); b[i] = clamp(bb * 0.78)
            case .vividGaming:
                // x^0.92 / x: lifts midtones, leaves black and white anchored.
                let lift = x > 0 ? pow(x, 0.92) / x : 1
                r[i] = clamp(br * 1.05 * lift); g[i] = clamp(bg * 1.04 * lift); b[i] = clamp(bb * 1.06 * lift)
            case .cinema:
                let lift = (1 - x) * 0.04
                r[i] = clamp(br * 0.98 + lift); g[i] = clamp(bg * 0.98 + lift); b[i] = clamp(bb * 0.99 + lift)
            case .fps:
                let boost = max(0, (0.55 - x) * 0.14)
                r[i] = clamp(br + boost); g[i] = clamp(bg + boost); b[i] = clamp(bb + boost * 0.9)
            case .rts:
                let lift = x > 0 ? pow(x, 0.88) / x : 1
                r[i] = clamp(br * 1.08 * lift); g[i] = clamp(bg * 1.06 * lift); b[i] = clamp(bb * 1.02 * lift)
            }
        }
        return (r, g, b)
    }
}
