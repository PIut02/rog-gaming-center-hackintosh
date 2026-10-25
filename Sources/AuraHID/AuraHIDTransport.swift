import Foundation
import IOKit
import IOKit.hid
import AuraCore

public struct AuraDeviceInfo: Equatable, Sendable {
    public let name: String
    public let vendorID: Int
    public let productID: Int
    public let serialNumber: String?
    public let transport: String
    public let usagePage: Int
    public let usage: Int
    public let maxFeatureReportSize: Int

    public var formattedVID: String { String(format: "0x%04X", vendorID) }
    public var formattedPID: String { String(format: "0x%04X", productID) }
    public var formattedUsage: String { String(format: "0x%04X / 0x%04X", usagePage, usage) }

    var descriptor: HIDInterfaceDescriptor {
        HIDInterfaceDescriptor(vendorID: vendorID, productID: productID, usagePage: usagePage,
                               usage: usage, maxFeatureReportSize: maxFeatureReportSize)
    }
}

/// macOS "Input Monitoring" state for this process. Opening the keyboard's HID
/// interfaces (and writing feature reports to them) is gated behind it.
public enum HIDAccess: Sendable {
    case granted
    case denied
    case undetermined
}

public enum AuraWriteResult: Equatable, Sendable {
    case success
    case noDevice
    case accessDenied
    case failed(Int32)
    /// A newer state was queued before this one was written; it was skipped on purpose.
    case superseded

    public var isSuccess: Bool { self == .success }
}

/// Talks to the ITE Aura controller over IOKit HID.
///
/// Writes are latest-wins: each submission is a complete lighting state, so while
/// one transaction is in flight only the newest pending one is kept. A color-picker
/// drag therefore never builds a backlog.
///
/// Callbacks (`onDeviceChange`, `onKey`, `onAccessChange`, write completions) are
/// delivered on the main thread.
public final class AuraHIDTransport {
    public var onDeviceChange: ((AuraDeviceInfo?) -> Void)?
    public var onKey: ((HardwareKey) -> Void)?
    public var onAccessChange: ((HIDAccess) -> Void)?

    /// The lighting interface packets are written to, if one was found.
    public private(set) var device: AuraDeviceInfo?
    /// Every ASUS interface currently enumerated, for diagnostics.
    public private(set) var interfaces: [AuraDeviceInfo] = []
    public private(set) var access: HIDAccess

    private let manager: IOHIDManager
    private let writeQueue = DispatchQueue(label: "rog.aura.hid.write", qos: .userInitiated)
    private let lock = NSLock()
    private var targets: [IOHIDDevice] = []
    private var pending: (packets: [[UInt8]], completion: ((AuraWriteResult) -> Void)?)?
    private var isDraining = false
    private var debouncer = KeyDebouncer()

    /// Settling time the ITE controller needs between feature reports.
    private static let interPacketDelay: useconds_t = 10_000

    public init(listenForKeys: Bool = true) {
        access = Self.checkAccess()
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: AuraInterfaceSelector.asusVendorID] as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, _ in
            guard let ctx else { return }
            Unmanaged<AuraHIDTransport>.fromOpaque(ctx).takeUnretainedValue().refreshDevices()
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, _ in
            guard let ctx else { return }
            Unmanaged<AuraHIDTransport>.fromOpaque(ctx).takeUnretainedValue().refreshDevices()
        }, context)

        if listenForKeys {
            IOHIDManagerRegisterInputValueCallback(manager, { ctx, _, _, value in
                guard let ctx, IOHIDValueGetIntegerValue(value) == 1 else { return }
                let element = IOHIDValueGetElement(value)
                guard let key = HardwareKey.decode(usagePage: IOHIDElementGetUsagePage(element),
                                                   usage: IOHIDElementGetUsage(element)) else { return }
                Unmanaged<AuraHIDTransport>.fromOpaque(ctx).takeUnretainedValue().deliver(key)
            }, context)
            IOHIDManagerRegisterInputReportCallback(manager, { ctx, _, _, _, reportID, report, length in
                guard let ctx, length >= 2 else { return }
                let bytes = Array(UnsafeBufferPointer(start: report, count: min(length, 4)))
                guard let key = HardwareKey.decode(reportID: reportID, report: bytes) else { return }
                Unmanaged<AuraHIDTransport>.fromOpaque(ctx).takeUnretainedValue().deliver(key)
            }, context)
        }

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        open()
    }

    deinit {
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    // MARK: - Access

    public static func checkAccess() -> HIDAccess {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: return .granted
        case kIOHIDAccessTypeDenied: return .denied
        default: return .undetermined
        }
    }

    /// Shows the system Input Monitoring prompt the first time; afterwards the user
    /// has to change it in System Settings. Reopens devices if access was granted.
    @discardableResult
    public func requestAccess() -> Bool {
        let granted = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        updateAccess()
        if granted { reopen() }
        return granted
    }

    /// Re-reads the access state, e.g. when the app becomes active after the user
    /// visited System Settings.
    public func updateAccess() {
        let current = Self.checkAccess()
        guard current != access else { return }
        access = current
        onAccessChange?(current)
        if current == .granted { reopen() }
    }

    public func reopen() {
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        open()
    }

    private func open() {
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result == kIOReturnNotPermitted, access != .denied {
            access = .denied
            onAccessChange?(.denied)
        }
        refreshDevices()
    }

    // MARK: - Devices

    public func refreshDevices() {
        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>).map(Array.init) ?? []
        let infos = devices.map(Self.info(for:))
        let selected = AuraInterfaceSelector.select(infos.map(\.descriptor))

        lock.lock()
        targets = selected.map { devices[$0] }
        lock.unlock()

        interfaces = infos
        let newDevice = selected.first.map { infos[$0] }
        if newDevice != device {
            device = newDevice
            onDeviceChange?(newDevice)
        }
    }

    private static func info(for device: IOHIDDevice) -> AuraDeviceInfo {
        func int(_ key: String) -> Int { IOHIDDeviceGetProperty(device, key as CFString) as? Int ?? 0 }
        return AuraDeviceInfo(
            name: IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "ASUS HID Device",
            vendorID: int(kIOHIDVendorIDKey),
            productID: int(kIOHIDProductIDKey),
            serialNumber: IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String,
            transport: IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? "USB",
            usagePage: int(kIOHIDPrimaryUsagePageKey),
            usage: int(kIOHIDPrimaryUsageKey),
            maxFeatureReportSize: int(kIOHIDMaxFeatureReportSizeKey)
        )
    }

    // MARK: - Keys

    private func deliver(_ key: HardwareKey) {
        guard debouncer.accept(key, at: ProcessInfo.processInfo.systemUptime) else { return }
        onKey?(key)
    }

    // MARK: - Writes

    /// Queues a full lighting transaction. If an older one is still waiting, it is
    /// dropped and its completion receives `.superseded`.
    public func send(_ packets: [[UInt8]], completion: ((AuraWriteResult) -> Void)? = nil) {
        lock.lock()
        let dropped = pending?.completion
        pending = (packets, completion)
        let startDrain = !isDraining
        isDraining = true
        lock.unlock()

        if let dropped { DispatchQueue.main.async { dropped(.superseded) } }
        if startDrain { writeQueue.async { [weak self] in self?.drain() } }
    }

    /// Blocking write for command-line use. Does not coalesce.
    public func sendAndWait(_ packets: [[UInt8]]) -> AuraWriteResult {
        writeQueue.sync { write(packets) }
    }

    private func drain() {
        while true {
            lock.lock()
            guard let job = pending else {
                isDraining = false
                lock.unlock()
                return
            }
            pending = nil
            lock.unlock()

            let result = write(job.packets)
            DispatchQueue.main.async { [weak self] in
                if result == .accessDenied, let self, self.access != .denied {
                    self.access = .denied
                    self.onAccessChange?(.denied)
                }
                job.completion?(result)
            }
        }
    }

    private func write(_ packets: [[UInt8]]) -> AuraWriteResult {
        lock.lock()
        let devices = targets
        lock.unlock()
        guard !devices.isEmpty else { return .noDevice }

        return HIDWriteLock.withLock {
            for device in devices {
                for packet in packets {
                    var buffer = packet
                    let status = IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, CFIndex(buffer[0]), &buffer, buffer.count)
                    if status == kIOReturnNotPermitted || status == kIOReturnExclusiveAccess {
                        return .accessDenied
                    }
                    if status != kIOReturnSuccess {
                        return .failed(status)
                    }
                    usleep(Self.interPacketDelay)
                }
            }
            return .success
        }
    }
}

/// Serializes writes between the app and the `rogauracore` CLI so their packet
/// sequences never interleave. Per-user, and never blocks for more than ~1 s.
enum HIDWriteLock {
    private static let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("rog-gaming-center.hid.lock")

    static func withLock<T>(_ body: () -> T) -> T {
        let fd = open(path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return body() }
        defer { close(fd) }

        var locked = false
        for _ in 0..<100 {
            if flock(fd, LOCK_EX | LOCK_NB) == 0 { locked = true; break }
            usleep(10_000)
        }
        defer { if locked { flock(fd, LOCK_UN) } }
        return body()
    }
}
