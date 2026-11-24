import Foundation
import IOKit
import ToolsmithKit

/// Reads the System Management Controller: the chip that knows the temperatures and fan speeds.
/// Reading needs no special permission. (Writing, to set a fan speed, needs root and is not done here.)
final class SMC {
    /// The structure the SMC driver exchanges. It must match the C layout exactly (80 bytes);
    /// `padding` stands where the C compiler leaves a gap.
    private struct Param {
        typealias Bytes = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                           UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
        struct Version { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0, release: UInt16 = 0 }
        struct PLimit { var version: UInt16 = 0, length: UInt16 = 0, cpu: UInt32 = 0, gpu: UInt32 = 0, mem: UInt32 = 0 }
        struct KeyInfo { var dataSize: UInt32 = 0, dataType: UInt32 = 0, dataAttributes: UInt8 = 0 }

        var key: UInt32 = 0
        var vers = Version()
        var pLimit = PLimit()
        var keyInfo = KeyInfo()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: Bytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private static let handleEvent: UInt32 = 2
    private static let readBytes: UInt8 = 5, writeBytes: UInt8 = 6, keyFromIndex: UInt8 = 8, keyInfo: UInt8 = 9

    private var connection: io_connect_t = 0
    /// Size and type of each key, asked once.
    private var info: [String: (size: UInt32, type: String)] = [:]

    init?() {
        guard MemoryLayout<Param>.stride == 80 else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else { return nil }
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    private func call(_ input: inout Param) -> Param? {
        var output = Param()
        var size = MemoryLayout<Param>.stride
        let status = IOConnectCallStructMethod(connection, Self.handleEvent, &input, MemoryLayout<Param>.stride, &output, &size)
        return status == kIOReturnSuccess && output.result == 0 ? output : nil
    }

    private static func code(_ key: String) -> UInt32 {
        key.utf8.prefix(4).reduce(0) { $0 << 8 | UInt32($1) }
    }

    private static func name(_ code: UInt32) -> String {
        String(bytes: [UInt8(code >> 24 & 0xFF), UInt8(code >> 16 & 0xFF), UInt8(code >> 8 & 0xFF), UInt8(code & 0xFF)], encoding: .ascii) ?? ""
    }

    private func keyInfo(_ key: String) -> (size: UInt32, type: String)? {
        if let known = info[key] { return known }
        var input = Param()
        input.key = Self.code(key)
        input.data8 = Self.keyInfo
        guard let output = call(&input) else { return nil }
        let found = (output.keyInfo.dataSize, Self.name(output.keyInfo.dataType))
        info[key] = found
        return found
    }

    /// The numeric value of a key, or nil when the key does not exist or is not a number.
    func value(_ key: String) -> Double? {
        guard let keyInfo = keyInfo(key), keyInfo.size > 0, keyInfo.size <= 32 else { return nil }
        var input = Param()
        input.key = Self.code(key)
        input.keyInfo.dataSize = keyInfo.size
        input.data8 = Self.readBytes
        guard let output = call(&input) else { return nil }
        let bytes = withUnsafeBytes(of: output.bytes) { Array($0.prefix(Int(keyInfo.size))) }
        return SMCValue.decode(type: keyInfo.type, bytes: bytes)
    }

    /// Whether the controller has this key.
    func has(_ key: String) -> Bool { keyInfo(key) != nil }

    /// A key's raw bytes, or nil when it does not exist or cannot be read.
    func bytes(_ key: String) -> [UInt8]? {
        guard let keyInfo = keyInfo(key), keyInfo.size > 0, keyInfo.size <= 32 else { return nil }
        var input = Param()
        input.key = Self.code(key)
        input.keyInfo.dataSize = keyInfo.size
        input.data8 = Self.readBytes
        guard let output = call(&input) else { return nil }
        return withUnsafeBytes(of: output.bytes) { Array($0.prefix(Int(keyInfo.size))) }
    }

    /// Writes raw bytes to a key that exists and has exactly that size. Only root may write;
    /// false when the key is missing, the size differs, or the write is refused.
    func writeBytes(_ key: String, _ bytes: [UInt8]) -> Bool {
        guard let keyInfo = keyInfo(key), bytes.count == Int(keyInfo.size) else { return false }
        var input = Param()
        input.key = Self.code(key)
        input.keyInfo.dataSize = keyInfo.size
        input.data8 = Self.writeBytes
        withUnsafeMutableBytes(of: &input.bytes) { buffer in
            for (index, byte) in bytes.enumerated() { buffer[index] = byte }
        }
        return call(&input) != nil
    }

    /// Writes a number to a key, in the key's own type. Only root may write; false when refused.
    func write(_ key: String, _ value: Double) -> Bool {
        guard let keyInfo = keyInfo(key), let bytes = SMCValue.encode(type: keyInfo.type, value: value), bytes.count == Int(keyInfo.size) else { return false }
        var input = Param()
        input.key = Self.code(key)
        input.keyInfo.dataSize = keyInfo.size
        input.data8 = Self.writeBytes
        withUnsafeMutableBytes(of: &input.bytes) { buffer in
            for (index, byte) in bytes.enumerated() { buffer[index] = byte }
        }
        return call(&input) != nil
    }

    /// Every key name the controller knows. Slow (thousands of calls): done once, off the main thread.
    func allKeys() -> [String] {
        guard let count = value("#KEY"), count.isFinite, count > 0, count < 100_000 else { return [] }
        var keys: [String] = []
        for index in 0..<UInt32(count) {
            var input = Param()
            input.data8 = Self.keyFromIndex
            input.data32 = index
            if let output = call(&input) { keys.append(Self.name(output.key)) }
        }
        return keys
    }

    /// The names of the temperature sensors this Mac has: those the summary or the sensor list use.
    func temperatureKeys() -> [String] {
        allKeys().filter { key in
            guard TemperatureSummary.wanted(key) || SensorCatalog.group(of: key) != nil,
                  let type = keyInfo(key)?.type, type == "flt " || type == "sp78" else { return false }
            return true
        }
    }

    func fans() -> [FanReading] {
        guard let count = value("FNum"), count.isFinite, count >= 1, count <= Double(FanCommand.maxFans) else { return [] }
        return (0..<Int(count)).compactMap { index in
            // A broken sensor can read NaN or nonsense; a fan turns between 0 and some thousands rpm.
            func rpm(_ key: String) -> Double? { value(key).flatMap { $0.isFinite && $0 >= 0 && $0 < 20_000 ? $0 : nil } }
            guard let speed = rpm("F\(index)Ac") else { return nil }
            return FanReading(index: index, rpm: speed, minimum: rpm("F\(index)Mn") ?? 0, maximum: rpm("F\(index)Mx") ?? 0)
        }
    }
}
