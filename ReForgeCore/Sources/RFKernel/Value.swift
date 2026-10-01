/// 構造化された小さな値(来歴の詳細・コンテンツの汎用パラメータ・移行時の JSON 木)。
/// 浮動小数は入れない(決定性のため。小数が要る値は Milli / Purity の整数で持つ)。
public indirect enum Value: Hashable, Sendable {
    case null
    case bool(Bool)
    case int(Int64)
    /// Int64 に入らない符号なしの値(乱数の状態など)。
    case uint(UInt64)
    case string(String)
    case array([Value])
    case object([String: Value])

    public subscript(key: String) -> Value? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    public var intValue: Int64? { if case .int(let v) = self { v } else { nil } }
    public var stringValue: String? { if case .string(let v) = self { v } else { nil } }
    public var boolValue: Bool? { if case .bool(let v) = self { v } else { nil } }
}

extension Value: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let i = try? c.decode(Int64.self) { self = .int(i) }
        else if let u = try? c.decode(UInt64.self) { self = .uint(u) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([Value].self) { self = .array(a) }
        else if let o = try? c.decode([String: Value].self) { self = .object(o) }
        else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Value に入らない値(小数は使わない)"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .int(let i): try c.encode(i)
        case .uint(let u): try c.encode(u)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}
