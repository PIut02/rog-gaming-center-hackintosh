import Foundation
import Testing
@testable import AuraCore

@Suite struct ColorTests {
    @Test func parsesSixDigitHexWithPrefixes() {
        #expect(AuraColor(hex: "#ff007f") == AuraColor(red: 255, green: 0, blue: 127))
        #expect(AuraColor(hex: "0x00FFFF") == AuraColor(red: 0, green: 255, blue: 255))
        #expect(AuraColor(hex: " 0a0b0c ") == AuraColor(red: 10, green: 11, blue: 12))
    }

    @Test func expandsThreeDigitHex() {
        #expect(AuraColor(hex: "f0a") == AuraColor(red: 255, green: 0, blue: 170))
    }

    @Test func rejectsInvalidHex() {
        #expect(AuraColor(hex: "") == nil)
        #expect(AuraColor(hex: "12345") == nil)
        #expect(AuraColor(hex: "gggggg") == nil)
    }

    @Test func hexRoundTrips() {
        let c = AuraColor(red: 1, green: 2, blue: 254)
        #expect(AuraColor(hex: c.hexString) == c)
        #expect(c.upperHexString == "0102FE")
    }
}

@Suite struct PacketTests {
    @Test func everyPacketIsSeventeenBytes() {
        let modes: [AuraMode] = [
            .off, .singleStatic(.red), .multiStatic([.red, .green, .blue, .white]),
            .colorCycle(.fast), .rainbow(.slow), .singleBreathing(.red, .blue, .medium),
            .multiBreathing([.red], .medium), .strobing(.white, .fast),
        ]
        for mode in modes {
            for pkt in AuraPacketBuilder.buildModeTransaction(mode: mode, brightness: 3) {
                #expect(pkt.count == AuraPacketBuilder.MESSAGE_LENGTH)
            }
        }
    }

    @Test func handshakeCarriesAsusSignature() {
        let pkt = AuraPacketBuilder.buildHandshakePacket()
        #expect(pkt[0] == 0x5a)
        #expect(String(decoding: pkt[1...14], as: UTF8.self) == "ASUS Tech.Inc.")
    }

    @Test func transactionIsFramedByHandshakeAndCommit() {
        let tx = AuraPacketBuilder.buildModeTransaction(mode: .singleStatic(.cyan), brightness: 2)
        #expect(tx.first == AuraPacketBuilder.buildHandshakePacket())
        #expect(tx[1] == AuraPacketBuilder.buildBrightnessPacket(level: 2))
        #expect(Array(tx.suffix(2)) == [AuraPacketBuilder.buildSetPacket(), AuraPacketBuilder.buildApplyPacket()])
    }

    @Test func brightnessIsClamped() {
        #expect(AuraPacketBuilder.buildBrightnessPacket(level: 9)[4] == 3)
        #expect(AuraPacketBuilder.buildBrightnessPacket(level: -4)[4] == 0)
    }

    @Test func staticColorPayloadLayout() {
        let tx = AuraPacketBuilder.buildModeTransaction(mode: .singleStatic(AuraColor(red: 1, green: 2, blue: 3)), brightness: 3)
        let pkt = tx[2]
        #expect(Array(pkt[0...7]) == [0x5d, 0xb3, 0x00, 0x00, 1, 2, 3, 0xeb])
    }

    @Test func multiStaticSendsBroadcastPlusFourZones() {
        let zones: [AuraColor] = [.red, .green, .blue, .white]
        let tx = AuraPacketBuilder.buildModeTransaction(mode: .multiStatic(zones), brightness: 3)
        // handshake, brightness, broadcast, 4 zones, set, apply
        #expect(tx.count == 9)
        for i in 0..<4 {
            #expect(tx[3 + i][2] == UInt8(i + 1))
            #expect(tx[3 + i][4] == zones[i].red)
        }
    }

    @Test func zeroBrightnessBlanksColors() {
        let tx = AuraPacketBuilder.buildModeTransaction(mode: .singleStatic(.red), brightness: 0)
        #expect(Array(tx[2][4...6]) == [0, 0, 0])
    }

    @Test func speedBytesAreDistinctAndOrdered() {
        let bytes = AuraSpeed.allCases.map(\.byteValue)
        #expect(bytes == bytes.sorted())
        #expect(Set(bytes).count == 3)
    }
}

@Suite struct ModelTests {
    @Test func modeCodableRoundTrips() throws {
        let modes: [AuraMode] = [
            .off, .singleStatic(.red), .multiStatic([.red, .green, .blue, .white]),
            .colorCycle(.fast), .singleBreathing(.red, .blue, .slow), .strobing(.white, .medium),
        ]
        for mode in modes {
            let data = try JSONEncoder().encode(mode)
            #expect(try JSONDecoder().decode(AuraMode.self, from: data) == mode)
        }
    }

    @Test func builtInPresetsAreWellFormed() {
        let presets = AuraPreset.builtInPresets
        #expect(Set(presets.map(\.id)).count == presets.count)
        for p in presets {
            if case .multiStatic(let zones) = p.mode { #expect(zones.count == 4) }
            #expect(!p.previewColors.isEmpty)
        }
    }
}
