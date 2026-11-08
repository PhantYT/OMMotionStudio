import Foundation

struct DumlPacket {
    let length: Int
    let sender: UInt8
    let receiver: UInt8
    let sequence: UInt16
    let attributes: UInt8
    let commandSet: UInt8
    let command: UInt8
    let payload: Data
    let raw: Data

    var isTelemetry: Bool {
        (commandSet == 0x04 && (command == 0x05 || command == 0x27))
            || (commandSet == 0x05 && command == 0x06)
    }

    var summary: String {
        "len=\(length) \(String(format: "0x%02X", sender))->\(String(format: "0x%02X", receiver)) seq=\(sequence) set=0x\(String(format: "%02X", commandSet)) cmd=0x\(String(format: "%02X", command)) payload=\(payload.hexString)"
    }
}

enum DumlCodec {
    static let app: UInt8 = 0x02
    static let gimbal: UInt8 = 0x04
    static let gimbalCommandSet: UInt8 = 0x04
    static let pwmCenter = 1024
    static let pwmMinimum = 363
    static let pwmMaximum = 1685

    // CRC8/CRC16 параметры из рабочего OM7P-проекта shaun-xenon/osmo-remote.
    private static func crc8(_ bytes: [UInt8]) -> UInt8 {
        var crc: UInt8 = 0x77
        for byte in bytes {
            crc ^= byte
            for _ in 0..<8 {
                crc = (crc & 0x01) != 0 ? (crc >> 1) ^ 0x8C : crc >> 1
            }
        }
        return crc
    }

    private static func crc16(_ bytes: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0xDF0C
        for byte in bytes {
            crc ^= UInt16(byte)
            for _ in 0..<8 {
                crc = (crc & 0x0001) != 0 ? (crc >> 1) ^ 0x8408 : crc >> 1
            }
        }
        return crc
    }

    static func buildPacket(
        commandSet: UInt8,
        command: UInt8,
        payload: Data = Data(),
        sequence: UInt16,
        attributes: UInt8 = 0x00
    ) -> Data {
        var body = Data([
            app,
            gimbal,
            UInt8(sequence & 0xFF),
            UInt8((sequence >> 8) & 0xFF),
            attributes,
            commandSet,
            command
        ])
        body.append(payload)

        let length = 4 + body.count + 2
        let lengthRaw = (length & 0x03FF) | (1 << 10)
        let header: [UInt8] = [
            0x55,
            UInt8(lengthRaw & 0xFF),
            UInt8((lengthRaw >> 8) & 0xFF)
        ]

        var packet = Data(header)
        packet.append(crc8(header))
        packet.append(body)

        let checksum = crc16(Array(body))
        packet.append(UInt8(checksum & 0xFF))
        packet.append(UInt8((checksum >> 8) & 0xFF))
        return packet
    }

    // GET_GIMBAL_POSITION: команда опроса текущего положения (0x04/0x02).
    static func buildPositionRequest(sequence: UInt16) -> Data {
        buildPacket(commandSet: gimbalCommandSet, command: 0x02, sequence: sequence)
    }

    // OM SPEED, подтверждённый автором osmo-remote на физическом DJI OM 7P.
    static func buildSpeedRotate(
        yaw: Int,
        pitch: Int,
        roll: Int = 0,
        duration: UInt8 = 10,
        sequence: UInt16
    ) -> Data {
        var payload = Data()
        appendInt16(yaw, to: &payload)
        appendInt16(roll, to: &payload)
        appendInt16(pitch, to: &payload)
        payload.append(contentsOf: [0x80, duration])

        return buildPacket(
            commandSet: gimbalCommandSet,
            command: 0x0C,
            payload: payload,
            sequence: sequence
        )
    }

    static func buildPWM(
        yaw: Int,
        pitch: Int,
        roll: Int = pwmCenter,
        sequence: UInt16
    ) -> Data {
        var payload = Data()
        appendUInt16(clamp(yaw, pwmMinimum, pwmMaximum), to: &payload)
        appendUInt16(clamp(roll, pwmMinimum, pwmMaximum), to: &payload)
        appendUInt16(clamp(pitch, pwmMinimum, pwmMaximum), to: &payload)
        return buildPacket(
            commandSet: gimbalCommandSet,
            command: 0x01,
            payload: payload,
            sequence: sequence
        )
    }

    static func buildAbsoluteRotate(
        yaw: Int,
        pitch: Int,
        roll: Int = 0,
        duration: UInt8 = 20,
        sequence: UInt16
    ) -> Data {
        var payload = Data()
        appendInt16(yaw, to: &payload)
        appendInt16(roll, to: &payload)
        appendInt16(pitch, to: &payload)
        payload.append(contentsOf: [0x05, duration])
        return buildPacket(
            commandSet: gimbalCommandSet,
            command: 0x14,
            payload: payload,
            sequence: sequence
        )
    }

    static func buildSetMode(_ mode: UInt8, sequence: UInt16) -> Data {
        buildPacket(
            commandSet: gimbalCommandSet,
            command: 0x4C,
            payload: Data([mode, 0x00]),
            sequence: sequence
        )
    }

    static func stickSpeed(_ axis: Double, maximum: Int) -> Int {
        let value = max(-1.0, min(1.0, axis))
        guard abs(value) >= 0.04 else { return 0 }
        return Int((value * Double(maximum)).rounded())
    }

    private static func appendInt16(_ value: Int, to data: inout Data) {
        let safe = max(Int(Int16.min), min(Int(Int16.max), value))
        let bits = UInt16(bitPattern: Int16(safe))
        appendUInt16(Int(bits), to: &data)
    }

    private static func appendUInt16(_ value: Int, to data: inout Data) {
        let safe = max(0, min(65535, value))
        data.append(UInt8(safe & 0xFF))
        data.append(UInt8((safe >> 8) & 0xFF))
    }

    private static func clamp(_ value: Int, _ minimum: Int, _ maximum: Int) -> Int {
        max(minimum, min(maximum, value))
    }
}

final class DumlParser {
    private var buffer = [UInt8]()

    func reset() {
        buffer.removeAll(keepingCapacity: true)
    }

    func feed(_ data: Data) -> [DumlPacket] {
        buffer.append(contentsOf: data)
        var packets: [DumlPacket] = []

        while true {
            guard !buffer.isEmpty else { break }

            if buffer[0] != 0x55 {
                if let index = buffer.firstIndex(of: 0x55) {
                    buffer.removeFirst(index)
                } else {
                    buffer.removeAll(keepingCapacity: true)
                    break
                }
            }

            guard buffer.count >= 4 else { break }
            let lengthRaw = Int(buffer[1]) | (Int(buffer[2]) << 8)
            let length = lengthRaw & 0x03FF

            guard length >= 13 else {
                buffer.removeFirst()
                continue
            }
            guard buffer.count >= length else { break }

            let header = Array(buffer[0..<3])
            let raw = Array(buffer[0..<length])
            let body = Array(raw[4..<(length - 2)])
            let receivedCRC = UInt16(raw[length - 2]) | (UInt16(raw[length - 1]) << 8)

            guard Self.crc8(header) == raw[3], Self.crc16(body) == receivedCRC else {
                buffer.removeFirst()
                continue
            }

            let packet = DumlPacket(
                length: length,
                sender: raw[4],
                receiver: raw[5],
                sequence: UInt16(raw[6]) | (UInt16(raw[7]) << 8),
                attributes: raw[8],
                commandSet: raw[9],
                command: raw[10],
                payload: Data(raw[11..<(length - 2)]),
                raw: Data(raw)
            )
            packets.append(packet)
            buffer.removeFirst(length)
        }

        return packets
    }

    private static func crc8(_ bytes: [UInt8]) -> UInt8 {
        var crc: UInt8 = 0x77
        for byte in bytes {
            crc ^= byte
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0x8C : crc >> 1
            }
        }
        return crc
    }

    private static func crc16(_ bytes: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0xDF0C
        for byte in bytes {
            crc ^= UInt16(byte)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0x8408 : crc >> 1
            }
        }
        return crc
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
