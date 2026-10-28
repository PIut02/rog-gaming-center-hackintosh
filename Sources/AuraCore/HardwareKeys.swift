import Foundation

/// ASUS vendor hotkeys delivered over the keyboard's HID vendor interface.
public enum HardwareKey: String, CaseIterable, Sendable {
    case rog
    case backlightUp
    case backlightDown
    case fan
    case touchpad
    case sleep

    public static let vendorUsagePages: Set<UInt32> = [0xFF31, 0xFF89, 0xFF00]

    /// Decodes an input element value (only presses, value == 1, should be passed in).
    public static func decode(usagePage: UInt32, usage: UInt32) -> HardwareKey? {
        guard vendorUsagePages.contains(usagePage) else { return nil }
        return decode(code: usage)
    }

    /// Decodes a raw `0x5A` input report, where byte 1 carries the key code.
    public static func decode(reportID: UInt32, report: [UInt8]) -> HardwareKey? {
        guard report.count >= 2, reportID == 0x5A || report[0] == 0x5A else { return nil }
        return decode(code: UInt32(report[1]))
    }

    static func decode(code: UInt32) -> HardwareKey? {
        switch code {
        case 0x38, 0xF8: return .rog
        case 0xC4: return .backlightUp
        case 0xC5: return .backlightDown
        case 0x99, 0xAE: return .fan
        case 0x6B: return .touchpad
        case 0x6C: return .sleep
        default: return nil
        }
    }

    public var debounceInterval: TimeInterval { self == .rog ? 0.25 : 0.15 }
}

/// Collapses the duplicate events a single press produces (value + report callbacks).
public struct KeyDebouncer: Sendable {
    private var lastAccepted: [HardwareKey: TimeInterval] = [:]

    public init() {}

    public mutating func accept(_ key: HardwareKey, at time: TimeInterval) -> Bool {
        if let last = lastAccepted[key], time - last < key.debounceInterval {
            return false
        }
        lastAccepted[key] = time
        return true
    }
}

// MARK: - Aura Interface Selection

/// HID properties needed to pick the lighting interface, independent of IOKit.
public struct HIDInterfaceDescriptor: Equatable, Sendable {
    public var vendorID: Int
    public var productID: Int
    public var usagePage: Int
    public var usage: Int
    public var maxFeatureReportSize: Int

    public init(vendorID: Int, productID: Int, usagePage: Int, usage: Int, maxFeatureReportSize: Int) {
        self.vendorID = vendorID
        self.productID = productID
        self.usagePage = usagePage
        self.usage = usage
        self.maxFeatureReportSize = maxFeatureReportSize
    }
}

public enum AuraInterfaceSelector {
    public static let asusVendorID = 0x0B05
    public static let knownProductIDs: Set<Int> = [
        0x1869, // GL503, GL703, FX503
        0x1854, // GL553, GL753
        0x1866, // GL504, GX501, GM501
        0x19B6, // GA401 (2021 N-KEY), GA503, G533, G733
        0x184A, 0x1837, 0x1822, 0x18CF, 0x18C6, 0x1A30,
    ]
    /// Aura packets are 17 bytes including the report ID.
    public static let minimumFeatureReportSize = 16

    /// Indices of the interfaces lighting packets should be written to.
    /// Only vendor-page interfaces that can take a full feature report qualify,
    /// so other ASUS devices (mice, docks, the plain keyboard interface) are never written to.
    public static func select(_ interfaces: [HIDInterfaceDescriptor]) -> [Int] {
        let asus = interfaces.indices.filter {
            interfaces[$0].vendorID == asusVendorID
                && interfaces[$0].maxFeatureReportSize >= minimumFeatureReportSize
        }
        let vendorPage = asus.filter { interfaces[$0].usagePage >= 0xFF00 }
        let knownVendorPage = vendorPage.filter { knownProductIDs.contains(interfaces[$0].productID) }

        var pool = !knownVendorPage.isEmpty ? knownVendorPage : vendorPage
        if pool.isEmpty {
            pool = asus.filter { knownProductIDs.contains(interfaces[$0].productID) }
        }
        guard let best = pool.max(by: { interfaces[$0].maxFeatureReportSize < interfaces[$1].maxFeatureReportSize }) else {
            return []
        }
        // One physical controller can expose several matching collections; never mix products.
        return pool.filter { interfaces[$0].productID == interfaces[best].productID }
    }
}
