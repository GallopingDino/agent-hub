import Foundation

// Just enough of the protobuf wire format to dig a nested field out of a message without its schema.
enum ProtobufReader {
    private static let varintType: UInt64 = 0
    private static let fixed64Type: UInt64 = 1
    private static let lengthDelimitedType: UInt64 = 2
    private static let fixed32Type: UInt64 = 5

    // Follows the field numbers down through nested messages; the first occurrence wins at each level.
    static func findBytes(in message: Data, path: [Int]) -> Data? {
        var current = message
        for number in path {
            guard let next = findLengthDelimitedField(in: current, number: number) else { return nil }
            current = next
        }
        return current
    }

    private static func findLengthDelimitedField(in message: Data, number: Int) -> Data? {
        let bytes = [UInt8](message)
        var offset = 0
        while offset < bytes.count {
            guard let key = readVarint(bytes, &offset) else { return nil }
            let wireType = key & 7
            let fieldNumber = Int(key >> 3)
            switch wireType {
            case varintType:
                guard readVarint(bytes, &offset) != nil else { return nil }
            case fixed64Type:
                offset += 8
            case fixed32Type:
                offset += 4
            case lengthDelimitedType:
                guard let length = readVarint(bytes, &offset), offset + Int(length) <= bytes.count else { return nil }
                if fieldNumber == number {
                    return Data(bytes[offset..<offset + Int(length)])
                }
                offset += Int(length)
            default:
                return nil
            }
        }
        return nil
    }

    private static func readVarint(_ bytes: [UInt8], _ offset: inout Int) -> UInt64? {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        while offset < bytes.count, shift < 64 {
            let byte = bytes[offset]
            offset += 1
            value |= UInt64(byte & 0x7f) << shift
            if byte & 0x80 == 0 { return value }
            shift += 7
        }
        return nil
    }
}
