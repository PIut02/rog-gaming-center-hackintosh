import Foundation
import CoreGraphics
import Observation
import AuraCore

/// Applies `DisplayProfile`s to every active display's gamma table.
///
/// Each non-standard apply starts from `CGDisplayRestoreColorSyncSettings()`, so the
/// baseline is always the display's current ColorSync calibration, not a stale copy.
/// The profile is reapplied after display reconfiguration and wake, which reset
/// gamma tables, and the system calibration is restored on quit.
@MainActor
@Observable
final class DisplayController {
    private(set) var profile: DisplayProfile
    private(set) var displayCount = 0
    private(set) var tableSize = 0
    private(set) var lastError: String?

    @ObservationIgnored var onChange: ((DisplayProfile) -> Void)?
    @ObservationIgnored private var reapplyWork: DispatchWorkItem?
    /// Only touch gamma after we've changed it, so Standard never disturbs
    /// Night Shift or other tools that adjust the display.
    @ObservationIgnored private var hasModifiedGamma = false

    init(profile: DisplayProfile) {
        self.profile = profile
        let context = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRegisterReconfigurationCallback({ _, flags, ctx in
            guard let ctx, !flags.contains(.beginConfigurationFlag) else { return }
            let controller = Unmanaged<DisplayController>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { controller.scheduleReapply() }
            }
        }, context)
        apply()
    }

    func select(_ profile: DisplayProfile) {
        guard profile != self.profile else { return }
        self.profile = profile
        apply()
        onChange?(profile)
    }

    /// Coalesces the burst of callbacks a single reconfiguration or wake produces.
    func scheduleReapply() {
        reapplyWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.apply() }
        reapplyWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func restoreSystemCalibration() {
        guard hasModifiedGamma else { return }
        CGDisplayRestoreColorSyncSettings()
        hasModifiedGamma = false
    }

    private func apply() {
        let displays = Self.activeDisplays()
        displayCount = displays.count
        tableSize = displays.first.map { Int(CGDisplayGammaTableCapacity($0)) } ?? 0
        lastError = nil
        guard profile != .standard else {
            restoreSystemCalibration()
            return
        }

        CGDisplayRestoreColorSyncSettings()
        hasModifiedGamma = true

        var failures = 0
        for display in displays {
            let capacity = CGDisplayGammaTableCapacity(display)
            guard capacity > 1 else { failures += 1; continue }

            var r = [CGGammaValue](repeating: 0, count: Int(capacity))
            var g = r, b = r
            var count: UInt32 = 0
            guard CGGetDisplayTransferByTable(display, capacity, &r, &g, &b, &count) == .success, count > 1 else {
                failures += 1
                continue
            }
            let n = Int(count)
            var out = profile.transform(red: Array(r.prefix(n)), green: Array(g.prefix(n)), blue: Array(b.prefix(n)))
            if CGSetDisplayTransferByTable(display, count, &out.red, &out.green, &out.blue) != .success {
                failures += 1
            }
        }
        if failures > 0 {
            lastError = "Could not adjust \(failures) of \(displays.count) display(s)."
        }
    }

    private static func activeDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }
}
