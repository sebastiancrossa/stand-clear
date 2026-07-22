func message(_ fields: [[UInt8]]) -> [UInt8] {
    fields.flatMap { $0 }
}

func stringField(_ number: UInt64, _ value: String) -> [UInt8] {
    lengthDelimitedField(number, Array(value.utf8))
}

func messageField(_ number: UInt64, _ value: [UInt8]) -> [UInt8] {
    lengthDelimitedField(number, value)
}

func lengthDelimitedField(_ number: UInt64, _ value: [UInt8]) -> [UInt8] {
    varint((number << 3) | 2) + varint(UInt64(value.count)) + value
}

func varintField(_ number: UInt64, _ value: UInt64) -> [UInt8] {
    varint(number << 3) + varint(value)
}

func varint(_ value: UInt64) -> [UInt8] {
    var value = value
    var bytes: [UInt8] = []
    repeat {
        var byte = UInt8(value & 0x7f)
        value >>= 7
        if value != 0 { byte |= 0x80 }
        bytes.append(byte)
    } while value != 0
    return bytes
}
