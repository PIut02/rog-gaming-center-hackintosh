import Testing
@testable import AuraCore

// MARK: - Profile Resolution

@Suite struct DeviceProfileTests {
    @Test func resolverDetectsGA401Controller() {
        #expect(AuraDeviceProfile.resolve(productID: 0x19B6) == .whiteSingleZone)
    }

    @Test func resolverKeepsOtherControllersRGB() {
        #expect(AuraDeviceProfile.resolve(productID: 0x1869) == .standardRGB)
        #expect(AuraDeviceProfile.resolve(productID: 0x1866) == .standardRGB)
    }

    @Test func resolverHandlesMissingOrZeroProductID() {
        #expect(AuraDeviceProfile.resolve(productID: nil) == .standardRGB)
        #expect(AuraDeviceProfile.resolve(productID: 0) == .standardRGB)
    }

    @Test func whiteKeyboardSupportsOnlyWhiteRenderableEffects() {
        #expect(AuraDeviceProfile.whiteSingleZone.supportedEffects == [.staticColor, .breathing, .strobe])
        #expect(AuraDeviceProfile.standardRGB.supportedEffects.count == AuraEffect.allCases.count)
    }

    @Test func zoneCountIsAlwaysAtLeastOne() {
        #expect(AuraDeviceProfile(isWhiteKeyboard: true, zoneCount: 0).zoneCount == 1)
    }
}

// MARK: - White-Keyboard Mode Normalization

@Suite struct WhiteKeyboardNormalizationTests {
    @Test func RGBOnlyEffectsCollapseToStaticWhite() {
        #expect(AuraMode.colorCycle(.fast).normalizedForWhiteKeyboard() == .singleStatic(.white))
        #expect(AuraMode.rainbow(.slow).normalizedForWhiteKeyboard() == .singleStatic(.white))
    }

    @Test func PerZoneModesCollapseToPrimaryColor() {
        let zones = [.rogRed, .cyan, .lime, .magenta]
        #expect(AuraMode.multiStatic(zones).normalizedForWhiteKeyboard() == .singleStatic(.rogRed))
        #expect(AuraMode.multiBreathing(zones, .medium).normalizedForWhiteKeyboard()
                == .singleBreathing(.rogRed, .black, .medium))
    }

    @Test func SingleZoneModesPassThrough() {
        let mode = AuraMode.singleBreathing(.blue, .black, .fast)
        #expect(mode.normalizedForWhiteKeyboard() == mode)
        #expect(AuraMode.strobing(.cyan, .slow).normalizedForWhiteKeyboard() == .strobing(.cyan, .slow))
    }
}

// MARK: - Packet Conformance for White Keyboards

@Suite struct WhiteKeyboardPacketTests {
    @Test func WhiteStaticPacketZeroesGreenAndBlue() {
        let tx = AuraPacketBuilder.buildModeTransaction(
            mode: .singleStatic(AuraColor(red: 0x12, green: 0xAB, blue: 0xCD)),
            brightness: 3, profile: .whiteSingleZone)
        let mode = tx.first { $0[0] == 0x5D && $0[1] == 0xB3 }!
        #expect(mode[4] == 0x12) // red channel preserved
        #expect(mode[5] == 0x00) // green forced to zero
        #expect(mode[6] == 0x00) // blue forced to zero
    }

    @Test func RGBStaticPacketKeepsAllChannels() {
        let tx = AuraPacketBuilder.buildModeTransaction(
            mode: .singleStatic(AuraColor(red: 0x12, green: 0xAB, blue: 0xCD)),
            brightness: 3, profile: .standardRGB)
        let mode = tx.first { $0[0] == 0x5D && $0[1] == 0xB3 }!
        #expect(mode[4] == 0x12 && mode[5] == 0xAB && mode[6] == 0xCD)
    }

    @Test func SingleZoneKeyboardSkipsPerZonePackets() {
        let zones = [.rogRed, .cyan, .lime, .magenta]
        let tx = AuraPacketBuilder.buildModeTransaction(mode: .multiStatic(zones), brightness: 3,
                                                        profile: .whiteSingleZone)
        // handshake + brightness + one broadcast mode packet + set + apply
        #expect(tx.count == 5)
        #expect(!tx.contains { $0[0] == 0x5D && $0[1] == 0xB3 && $0[2] != 0x00 })
    }

    @Test func MultiZoneKeyboardStillSendsPerZonePackets() {
        let zones = [.rogRed, .cyan, .lime, .magenta]
        let tx = AuraPacketBuilder.buildModeTransaction(mode: .multiStatic(zones), brightness: 3,
                                                        profile: .standardRGB)
        // handshake + brightness + broadcast + 4 zones + set + apply
        #expect(tx.count == 9)
    }

    @Test func DefaultProfileIsStandardRGB() {
        let tx = AuraPacketBuilder.buildModeTransaction(mode: .multiStatic([.rogRed, .cyan, .lime, .magenta]))
        #expect(tx.count == 9)
    }
}

// MARK: - LightingState Profile Transactions

@Suite struct LightingStateProfileTests {
    @Test func WhiteProfileNormalizesStateModeBeforeBuilding() {
        var state = LightingState(mode: .rainbow(.fast), brightness: 3, isOn: true, presetID: nil)
        let tx = state.transaction(for: .whiteSingleZone)
        let mode = tx.first { $0[0] == 0x5D && $0[1] == 0xB3 }!
        #expect(mode[3] == 0x00) // degraded to static
        #expect(mode[5] == 0x00 && mode[6] == 0x00)
    }

    @Test func OffTransactionIsProfileIndependent() {
        let state = LightingState(mode: .singleStatic(.rogRed), brightness: 2, isOn: false, presetID: nil)
        #expect(state.transaction(for: .whiteSingleZone) == state.transaction(for: .standardRGB))
        #expect(state.transaction == AuraPacketBuilder.buildModeTransaction(mode: .off, brightness: 0))
    }
}
