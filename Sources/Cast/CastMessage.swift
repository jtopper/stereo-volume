import Foundation

// Manual proto2 implementation of cast_channel.CastMessage.
// Field numbers match cast_channel.proto from Chromium exactly.
struct CastMessage {
    var sourceID:      String = "sender-0"
    var destinationID: String = "receiver-0"
    var namespace:     String = ""
    var payloadUtf8:   String = ""

    // MARK: - Encode

    func encode() -> Data {
        var buf = Data()
        buf.appendVarintField(1, value: 0)               // protocol_version = CAST_V2_1_0
        buf.appendStringField(2, value: sourceID)
        buf.appendStringField(3, value: destinationID)
        buf.appendStringField(4, value: namespace)
        buf.appendVarintField(5, value: 0)               // payload_type = STRING
        buf.appendStringField(6, value: payloadUtf8)
        return buf
    }

    // MARK: - Decode

    enum DecodeError: Error { case truncated, invalidUtf8 }

    init() {}

    init(data: Data) throws {
        var i = data.startIndex
        while i < data.endIndex {
            let tag = try data.readVarint(at: &i)
            let field = Int(tag) >> 3
            let wire  = Int(tag) & 0x7
            switch (field, wire) {
            case (1, 0): _ = try data.readVarint(at: &i)           // protocol_version (ignore)
            case (2, 2): sourceID      = try data.readString(at: &i)
            case (3, 2): destinationID = try data.readString(at: &i)
            case (4, 2): namespace     = try data.readString(at: &i)
            case (5, 0): _ = try data.readVarint(at: &i)           // payload_type (ignore)
            case (6, 2): payloadUtf8   = try data.readString(at: &i)
            case (7, 2): try data.skipBytes(at: &i)                 // payload_binary (unused)
            default:     try data.skipField(wire: wire, at: &i)
            }
        }
    }
}

// MARK: - Proto wire-format helpers

private extension Data {
    mutating func appendVarint(_ v: UInt64) {
        var v = v
        repeat {
            var byte = UInt8(v & 0x7F)
            v >>= 7
            if v != 0 { byte |= 0x80 }
            append(byte)
        } while v != 0
    }

    mutating func appendVarintField(_ field: Int, value: Int) {
        appendVarint(UInt64(bitPattern: Int64(field << 3 | 0)))
        appendVarint(UInt64(bitPattern: Int64(value)))
    }

    mutating func appendStringField(_ field: Int, value: String) {
        let bytes = Data(value.utf8)
        appendVarint(UInt64(field << 3 | 2))
        appendVarint(UInt64(bytes.count))
        append(bytes)
    }
}

extension Data {
    fileprivate func readVarint(at i: inout Index) throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while i < endIndex {
            let byte = self[i]; i = index(after: i)
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
            if shift >= 64 { throw CastMessage.DecodeError.truncated }
        }
        throw CastMessage.DecodeError.truncated
    }

    fileprivate func readString(at i: inout Index) throws -> String {
        let len = Int(try readVarint(at: &i))
        guard i <= endIndex, distance(from: i, to: endIndex) >= len
        else { throw CastMessage.DecodeError.truncated }
        let end = index(i, offsetBy: len)
        guard let s = String(data: self[i..<end], encoding: .utf8)
        else { throw CastMessage.DecodeError.invalidUtf8 }
        i = end
        return s
    }

    fileprivate func skipBytes(at i: inout Index) throws {
        _ = try readString(at: &i)   // same framing as a string field
    }

    fileprivate func skipField(wire: Int, at i: inout Index) throws {
        switch wire {
        case 0: _ = try readVarint(at: &i)
        case 1: i = index(i, offsetBy: 8)           // 64-bit
        case 2: try skipBytes(at: &i)
        case 5: i = index(i, offsetBy: 4)           // 32-bit
        default: throw CastMessage.DecodeError.truncated
        }
    }
}
