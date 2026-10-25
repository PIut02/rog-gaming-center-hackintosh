import Foundation
import Testing
@testable import AuraCore

@Suite struct LightingStateTests {
    @Test func offStateSendsOffTransaction() {
        var s = LightingState.default
        s.isOn = false
        #expect(s.transaction == AuraPacketBuilder.buildModeTransaction(mode: .off, brightness: 0))
        #expect(s.effectiveBrightness == 0)
    }

    @Test func levelZeroTurnsOffButKeepsBrightness() {
        var s = LightingState.default
        s.setLevel(2)
        s.setLevel(0)
        #expect(!s.isOn)
        #expect(s.brightness == 2)
        s.setLevel(9)
        #expect(s.isOn && s.brightness == 3)
    }

    @Test func offModeIsNeverStored() {
        let s = LightingState(mode: .off, brightness: 3, isOn: true, presetID: nil)
        #expect(!s.mode.isOff)
    }
}

@Suite struct ModeEditingTests {
    @Test func convertingKeepsColorsAndSpeed() {
        let breathing = AuraMode.singleBreathing(.cyan, .blue, .fast)
        #expect(breathing.converted(to: .strobe) == .strobing(.cyan, .fast))
        #expect(AuraMode.singleStatic(.red).converted(to: .breathing) == .singleBreathing(.red, .black, .medium))
        #expect(breathing.converted(to: .breathing) == breathing)
    }

    @Test func zoneEditingPromotesToMultiStatic() {
        let mode = AuraMode.singleStatic(.red).settingZone(2, to: .blue)
        #expect(mode == .multiStatic([.red, .red, .blue, .red]))
        #expect(mode.settingZone(7, to: .green) == mode)
        #expect(mode.settingIndividualZones(false) == .singleStatic(.red))
    }

    @Test func speedOnlyAppliesToAnimatedModes() {
        #expect(AuraMode.singleStatic(.red).withSpeed(.fast) == .singleStatic(.red))
        #expect(AuraMode.rainbow(.slow).withSpeed(.fast).speed == .fast)
    }

    @Test func previewColorsHaveFourZones() {
        let modes: [AuraMode] = [.off, .singleStatic(.red), .multiStatic([.red, .green, .blue, .white]),
                                 .colorCycle(.medium), .rainbow(.fast), .singleBreathing(.red, .blue, .slow),
                                 .strobing(.white, .fast)]
        for mode in modes {
            for t in [0.0, 0.7, 3.1] {
                #expect(mode.previewColors(at: t).count == 4)
            }
        }
        #expect(AuraMode.multiStatic([.red, .green, .blue, .white]).previewColors(at: 5) == [.red, .green, .blue, .white])
    }

    @Test func hueWrapsAndHitsPrimaries() {
        #expect(AuraColor.hue(0) == AuraColor(red: 255, green: 0, blue: 0))
        #expect(AuraColor.hue(1.0 / 3) == AuraColor(red: 0, green: 255, blue: 0))
        #expect(AuraColor.hue(1.25) == AuraColor.hue(0.25))
    }
}

@Suite struct HardwareKeyTests {
    @Test func decodesVendorUsages() {
        #expect(HardwareKey.decode(usagePage: 0xFF31, usage: 0x38) == .rog)
        #expect(HardwareKey.decode(usagePage: 0xFF89, usage: 0xC4) == .backlightUp)
        #expect(HardwareKey.decode(usagePage: 0xFF00, usage: 0x6C) == .sleep)
    }

    @Test func ignoresStandardKeyboardPage() {
        // Page 0x07 is the standard keyboard; usage 0x38 there is "/" and must not fire the ROG action.
        #expect(HardwareKey.decode(usagePage: 0x07, usage: 0x38) == nil)
    }

    @Test func decodesReports() {
        #expect(HardwareKey.decode(reportID: 0x5A, report: [0x5A, 0xC5]) == .backlightDown)
        #expect(HardwareKey.decode(reportID: 0x01, report: [0x01, 0xC5]) == nil)
        #expect(HardwareKey.decode(reportID: 0x5A, report: [0x5A]) == nil)
    }

    @Test func debouncerCollapsesDuplicatesPerKey() {
        var d = KeyDebouncer()
        let results = [
            d.accept(.rog, at: 10),
            d.accept(.rog, at: 10.1),
            d.accept(.backlightUp, at: 10.1),
            d.accept(.rog, at: 10.3),
        ]
        #expect(results == [true, false, true, true])
    }
}

@Suite struct InterfaceSelectorTests {
    func iface(pid: Int = 0x1869, page: Int, feature: Int, vid: Int = 0x0B05) -> HIDInterfaceDescriptor {
        HIDInterfaceDescriptor(vendorID: vid, productID: pid, usagePage: page, usage: 1, maxFeatureReportSize: feature)
    }

    @Test func picksVendorLightingInterfaceOnly() {
        let list = [
            iface(page: 0x01, feature: 0),          // plain keyboard
            iface(page: 0xFF89, feature: 64),       // Aura
            iface(pid: 0x1234, page: 0x01, feature: 8), // ASUS mouse
        ]
        #expect(AuraInterfaceSelector.select(list) == [1])
    }

    @Test func neverWritesToOtherVendors() {
        #expect(AuraInterfaceSelector.select([iface(page: 0xFF89, feature: 64, vid: 0x046D)]).isEmpty)
    }

    @Test func prefersKnownProductAndDoesNotMixProducts() {
        let list = [iface(pid: 0x7777, page: 0xFF00, feature: 64), iface(pid: 0x1869, page: 0xFF89, feature: 64)]
        #expect(AuraInterfaceSelector.select(list) == [1])
    }

    @Test func emptyWhenNothingQualifies() {
        #expect(AuraInterfaceSelector.select([iface(pid: 0x7777, page: 0x0C, feature: 4)]).isEmpty)
    }
}

@Suite struct DisplayProfileTests {
    let identity: [Float] = (0..<256).map { Float($0) / 255 }

    @Test func standardIsIdentity() {
        let out = DisplayProfile.standard.transform(red: identity, green: identity, blue: identity)
        #expect(out.red == identity && out.green == identity && out.blue == identity)
    }

    @Test func profilesStayInRangeAndKeepLength() {
        for profile in DisplayProfile.allCases {
            let out = profile.transform(red: identity, green: identity, blue: identity)
            for channel in [out.red, out.green, out.blue] {
                #expect(channel.count == identity.count)
                #expect(channel.allSatisfy { (0...1).contains($0) })
            }
        }
    }

    @Test func eyeCareReducesBlue() {
        let out = DisplayProfile.eyeCare.transform(red: identity, green: identity, blue: identity)
        #expect(out.blue[255] < out.red[255])
    }

    @Test func rawValuesAreStable() {
        // Persisted in settings; changing them would reset users' choice.
        #expect(DisplayProfile.allCases.map(\.rawValue) == ["standard", "vivid_gaming", "eye_care", "cinema", "fps", "rts"])
    }
}
