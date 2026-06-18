import Foundation
import CryptoKit
import CoreBluetooth

// MARK: - BLE UUIDs
// Source: https://blraaz.me/reverse-engineering/2021/08/29/bluetooth-reverse-engineering.html
// and https://github.com/tristanseifert/pax-controller-test

enum PaxUUIDs {
    static let serviceUUID        = CBUUID(string: "8E320200-64D2-11E6-BDF4-0800200C9A66")
    static let readCharUUID       = CBUUID(string: "8E320201-64D2-11E6-BDF4-0800200C9A66")
    static let writeCharUUID      = CBUUID(string: "8E320202-64D2-11E6-BDF4-0800200C9A66")
    static let notifyCharUUID     = CBUUID(string: "8E320203-64D2-11E6-BDF4-0800200C9A66")

    static let deviceInfoService  = CBUUID(string: "180A")
    static let serialNumberChar   = CBUUID(string: "2A25")
    static let modelNumberChar    = CBUUID(string: "2A24")
    static let firmwareRevChar    = CBUUID(string: "2A26")
    static let manufacturerChar   = CBUUID(string: "2A29")
}

// MARK: - Message Types
// All message types discovered from reverse engineering the Android app.
// Reference: https://blraaz.me/reverse-engineering/2021/08/29/bluetooth-reverse-engineering.html

enum PaxMessageType: UInt8 {
    case actualTemp         = 0x01  // Current oven temp; 16-bit LE, °C × 10
    case heaterSetPoint     = 0x02  // Target temp; 16-bit LE, °C × 10
    case battery            = 0x03  // State of charge; 1 byte, 0–100
    case usage              = 0x04
    case usageLimit         = 0x05
    case lockStatus         = 0x06  // 1 byte; 0 = unlocked, 1 = locked
    case chargeStatus       = 0x07
    case podInserted        = 0x08  // Era only
    case time               = 0x09
    case displayName        = 0x0A  // 1 byte length + UTF-8 bytes
    case heaterRanges       = 0x11
    case dynamicMode        = 0x13  // 1 byte dynamic heating mode (Pax 3)
    case colorTheme         = 0x14
    case brightness         = 0x15
    case hapticMode         = 0x17
    case supportedAttribs   = 0x18  // 64-bit bitfield of supported message types
    case heatingParams      = 0x19
    case uiMode             = 0x1B
    case shellColor         = 0x1C
    case lowSoCMode         = 0x1E
    case currentTargetTemp  = 0x1F  // Current PID target; 16-bit LE, °C × 10 (Pax 3)
    case heatingState       = 0x20  // Current oven state byte (Pax 3)
    case haptics            = 0x28
    case statusUpdate       = 0xFE  // Request status; 64-bit LE bitfield of desired attrs
}

// MARK: - Heating State
enum PaxHeatingState: UInt8, CustomStringConvertible {
    case off          = 0x00
    case standby      = 0x01
    case heating      = 0x02
    case ready        = 0x03
    case cooling      = 0x05
    case boostMode    = 0x08

    var description: String {
        switch self {
        case .off:       return "Off"
        case .standby:   return "Standby"
        case .heating:   return "Heating"
        case .ready:     return "Ready"
        case .cooling:   return "Cooling"
        case .boostMode: return "Boost"
        }
    }
}

// MARK: - Dynamic Mode (PAX 3 heating profile)
enum PaxDynamicMode: UInt8, CaseIterable, Identifiable {
    case standard   = 0x00
    case boost      = 0x01
    case efficiency = 0x02
    case stealth    = 0x03
    case flavor     = 0x04

    var id: UInt8 { rawValue }

    var label: String {
        switch self {
        case .standard:   return "Standard"
        case .boost:      return "Boost"
        case .efficiency: return "Efficiency"
        case .stealth:    return "Stealth"
        case .flavor:     return "Flavor"
        }
    }

    var icon: String {
        switch self {
        case .standard:   return "dial.medium"
        case .boost:      return "flame.fill"
        case .efficiency: return "leaf.fill"
        case .stealth:    return "moon.fill"
        case .flavor:     return "sparkles"
        }
    }
}

// MARK: - Preset temperatures (°C)
enum PaxPresetTemp: Int, CaseIterable, Identifiable {
    case t180 = 180
    case t193 = 193
    case t204 = 204
    case t215 = 215

    var id: Int { rawValue }
    var label: String { "\(rawValue)°C" }

    var encodedValue: UInt16 { UInt16(rawValue * 10) }
}

// MARK: - Packet Layer
// Packets are AES-128 OFB encrypted.
// Plaintext packet: [messageType: 1 byte][payload: variable][padding to 16 bytes]
// Wire format: [ciphertext: 16 bytes][IV: 16 bytes] — IV is last 16 bytes of 32-byte packet.
// Key derivation: AES-128-ECB(serialNumber + serialNumber encoded as UTF-8, sharedKey)
// Shared key: F7C866C38F78753086293BD57DD32540 (from public reverse engineering research)

struct PaxCrypto {
    // Shared key sourced from public reverse engineering documentation.
    // This is not a secret — it is hardcoded in every PAX mobile app and
    // documented in multiple public security research posts.
    private static let sharedKeyBytes: [UInt8] = [
        0xF7, 0xC8, 0x66, 0xC3, 0x8F, 0x78, 0x75, 0x30,
        0x86, 0x29, 0x3B, 0xD5, 0x7D, 0xD3, 0x25, 0x40
    ]

    static func deriveKey(serialNumber: String) throws -> SymmetricKey {
        let serial = serialNumber.uppercased()
        let doubled = serial + serial
        guard let raw = doubled.data(using: .utf8) else {
            throw PaxError.keyDerivationFailed("Serial '\(serialNumber)' is not valid UTF-8")
        }
        var serialData = Data(repeating: 0, count: 16)
        serialData.replaceSubrange(0..<min(raw.count, 16), with: raw.prefix(16))
        let sharedKey = SymmetricKey(data: Data(sharedKeyBytes))

        // AES-128-ECB: encrypt serialData with sharedKey
        let derived = try aesECBEncrypt(data: serialData, key: sharedKey)
        let sessionKey = SymmetricKey(data: Data(derived.prefix(16)))
        let keyHex = derived.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " ")
        NSLog("[PAX] Session key: [%@]", keyHex)
        return sessionKey
    }

    static func encrypt(plaintext: Data, key: SymmetricKey) throws -> Data {
        // Pad or truncate to 16 bytes
        var block = Data(count: 16)
        let copyLen = min(plaintext.count, 16)
        block.replaceSubrange(0..<copyLen, with: plaintext.prefix(copyLen))

        // Generate random 16-byte IV
        var ivBytes = [UInt8](repeating: 0, count: 16)
        let result = SecRandomCopyBytes(kSecRandomDefault, 16, &ivBytes)
        guard result == errSecSuccess else { throw PaxError.encryptionFailed("SecRandomCopyBytes failed") }
        let iv = Data(ivBytes)

        let ciphertext = try aesOFBCrypt(data: block, key: key, iv: iv)
        return ciphertext + iv
    }

    static func decrypt(packet: Data, key: SymmetricKey) throws -> (plaintext: Data, iv: Data, ciphertext: Data) {
        guard packet.count == 32 else {
            throw PaxError.decryptionFailed("Expected 32-byte packet, got \(packet.count)")
        }
        // PAX packet layout: [ciphertext 16 bytes][IV 16 bytes]
        let ciphertext = Data(packet.prefix(16))
        let iv         = Data(packet.suffix(16))
        // Compute keystream = AES_ECB(key, iv) for logging
        let keystream  = (try? aesECBEncrypt(data: iv, key: key).prefix(16)) ?? Data()
        let plaintext  = try aesOFBCrypt(data: ciphertext, key: key, iv: iv)
        let ivHex  = iv.map        { String(format:"%02X",$0) }.joined(separator:" ")
        let ksHex  = keystream.map { String(format:"%02X",$0) }.joined(separator:" ")
        let ctHex  = ciphertext.map{ String(format:"%02X",$0) }.joined(separator:" ")
        let ptHex  = plaintext.map { String(format:"%02X",$0) }.joined(separator:" ")
        NSLog("[PAX] DEC iv=[%@] ks=[%@] ct=[%@] pt=[%@]", ivHex, ksHex, ctHex, ptHex)
        return (plaintext, iv, ciphertext)
    }

    // MARK: - CommonCrypto wrappers

    private static func aesECBEncrypt(data: Data, key: SymmetricKey) throws -> Data {
        // AES-ECB(key, block) == AES-CBC(key, iv=zeros, block) for a single 16-byte block.
        // Use CBC mode which is reliably implemented in CommonCrypto unlike ECB.
        guard data.count == kCCBlockSizeAES128 else {
            throw PaxError.keyDerivationFailed("ECB input must be exactly 16 bytes, got \(data.count)")
        }
        let keyBytes  = key.withUnsafeBytes { bytes in Array(bytes.bindMemory(to: UInt8.self)) }
        let zeroIV    = [UInt8](repeating: 0, count: kCCBlockSizeAES128)
        let inBytes   = Array(data)   // copy to avoid overlapping-access error
        // CBC with zero IV + PKCS7: output is 32 bytes (data block + padding block); take first 16.
        var out       = Data(count: kCCBlockSizeAES128 * 2)
        let outCount  = out.count
        var outLen    = 0
        let status: CCCryptorStatus = out.withUnsafeMutableBytes { outPtr in
            CCCrypt(
                CCOperation(kCCEncrypt),
                CCAlgorithm(kCCAlgorithmAES),
                CCOptions(kCCOptionPKCS7Padding),   // CBC + PKCS7, no ECB flag
                keyBytes, keyBytes.count,
                zeroIV,                              // zero IV → CBC first block == ECB
                inBytes, inBytes.count,
                outPtr.baseAddress!, outCount,
                &outLen
            )
        }
        guard status == kCCSuccess else { throw PaxError.keyDerivationFailed("CCCrypt CBC(ECB) status \(status)") }
        return Data(out.prefix(kCCBlockSizeAES128))     // discard PKCS7 padding block
    }

    private static func aesOFBCrypt(data: Data, key: SymmetricKey, iv: Data) throws -> Data {
        // Manual OFB: keystream = AES-ECB(IV), AES-ECB(AES-ECB(IV)), ...
        // XOR each keystream block with the corresponding data block.
        // This avoids CommonCrypto's kCCModeOFB which is unreliable on iOS.
        var keystream = Data(iv)
        var result    = Data(capacity: data.count)
        var offset    = 0
        while offset < data.count {
            keystream = Data(try aesECBEncrypt(data: keystream, key: key).prefix(kCCBlockSizeAES128))
            let blockEnd = min(offset + kCCBlockSizeAES128, data.count)
            for i in offset..<blockEnd {
                result.append(data[i] ^ keystream[i - offset])
            }
            offset += kCCBlockSizeAES128
        }
        return result
    }
}

// MARK: - Packet Builder / Parser

struct PaxPacket {
    let type: PaxMessageType
    let payload: Data

    init(type: PaxMessageType, payload: Data = Data()) {
        self.type = type
        self.payload = payload
    }

    func encode(key: SymmetricKey) throws -> Data {
        var plaintext = Data([type.rawValue]) + payload
        if plaintext.count < 16 {
            plaintext.append(contentsOf: Data(repeating: 0, count: 16 - plaintext.count))
        }
        return try PaxCrypto.encrypt(plaintext: plaintext.prefix(16), key: key)
    }

    static func decode(data: Data, key: SymmetricKey) throws -> (packet: PaxPacket, plaintext: Data) {
        let result = try PaxCrypto.decrypt(packet: data, key: key)
        let plaintext = Data(result.plaintext)
        guard !plaintext.isEmpty else {
            throw PaxError.decryptionFailed("Decrypted to empty plaintext")
        }
        guard let type = PaxMessageType(rawValue: plaintext[0]) else {
            throw PaxError.unknownMessageType(plaintext[0])
        }
        let packet = PaxPacket(type: type, payload: Data(plaintext.dropFirst()))
        return (packet, plaintext)
    }
}

// MARK: - Status Request Builder

extension PaxPacket {
    static func statusRequest(attributes: [PaxMessageType]) -> PaxPacket {
        var bitfield: UInt64 = 0
        for attr in attributes {
            let bit = UInt64(attr.rawValue)
            guard bit < 64 else { continue }
            bitfield |= (1 << bit)
        }
        var le = bitfield.littleEndian
        let payload = withUnsafeBytes(of: &le) { Data($0) }
        return PaxPacket(type: .statusUpdate, payload: payload)
    }

    static func setTemperature(_ celsius: Int) -> PaxPacket {
        var encoded = UInt16(celsius * 10).littleEndian
        let payload = withUnsafeBytes(of: &encoded) { Data($0) }
        return PaxPacket(type: .heaterSetPoint, payload: payload)
    }

    static func setDynamicMode(_ mode: PaxDynamicMode) -> PaxPacket {
        PaxPacket(type: .dynamicMode, payload: Data([mode.rawValue]))
    }
}

// MARK: - Parser helpers

extension PaxPacket {
    var temperatureCelsius: Double? {
        guard payload.count >= 2 else { return nil }
        let raw = UInt16(payload[0]) | (UInt16(payload[1]) << 8)
        let celsius = Double(raw) / 10.0
        guard celsius >= 0, celsius <= 300 else { return nil }
        return celsius
    }

    var batteryLevel: Int? {
        guard payload.count >= 1 else { return nil }
        return Int(payload[0])
    }

    var heatingState: PaxHeatingState? {
        guard payload.count >= 1 else { return nil }
        return PaxHeatingState(rawValue: payload[0])
    }

    var lockState: Bool? {
        guard payload.count >= 1 else { return nil }
        return payload[0] != 0
    }

    var dynamicMode: PaxDynamicMode? {
        guard payload.count >= 1 else { return nil }
        return PaxDynamicMode(rawValue: payload[0])
    }
}

// MARK: - Errors

enum PaxError: Error, LocalizedError {
    case keyDerivationFailed(String)
    case encryptionFailed(String)
    case decryptionFailed(String)
    case unknownMessageType(UInt8)
    case notConnected
    case missingCharacteristic(String)

    var errorDescription: String? {
        switch self {
        case .keyDerivationFailed(let s):   return "Key derivation failed: \(s)"
        case .encryptionFailed(let s):      return "Encryption failed: \(s)"
        case .decryptionFailed(let s):      return "Decryption failed: \(s)"
        case .unknownMessageType(let t):    return "Unknown message type: 0x\(String(t, radix: 16))"
        case .notConnected:                 return "Not connected to device"
        case .missingCharacteristic(let s): return "Missing characteristic: \(s)"
        }
    }
}
