import Foundation
import RFKernel

/// バイト列が決まる JSON(保存の正準形)。同じ値なら、いつ・どの端末で・どの順に作った値でも同じバイト列になる。
///
/// 標準の JSONEncoder(.sortedKeys)だけでは揺れる所がある:
/// - `Set` は要素をハッシュの順に書く(起動ごとに変わる)。
/// - 文字列でもコーディングキーでもないキーの辞書(`[ProvenanceID: Int]` など)は [キー, 値, キー, 値…] の配列になり、
///   これもハッシュの順。
/// - キーの並べ方・文字のエスケープは実装(Darwin と Linux)ごとに違い得る。
///
/// ここでは値をいったん `Value` の木にし(Set と配列になった辞書は要素の正準のバイト列の順に並べ直す)、
/// 木を自前で書き出す(オブジェクトのキーは UTF-8 のバイト順、エスケープは最小限)。読むのは標準の JSONDecoder でよい。
public enum CanonicalJSON {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        Data(bytes(try tree(value)))
    }

    /// 値を Value の木にする(Set と配列の辞書は並べ直し済み)。
    public static func tree<T: Encodable>(_ value: T) throws -> Value {
        try ValueEncoding.box(value, path: []).finish()
    }

    /// Value の木を正準のバイト列にする。
    public static func bytes(_ v: Value) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(1024)
        write(v, &out)
        return out
    }

    static func write(_ v: Value, _ out: inout [UInt8]) {
        switch v {
        case .null: out += Array("null".utf8)
        case .bool(let b): out += Array((b ? "true" : "false").utf8)
        case .int(let i): out += Array(String(i).utf8)
        case .uint(let u): out += Array(String(u).utf8)
        case .string(let s): writeString(s, &out)
        case .array(let a):
            out.append(UInt8(ascii: "["))
            for (i, e) in a.enumerated() {
                if i > 0 { out.append(UInt8(ascii: ",")) }
                write(e, &out)
            }
            out.append(UInt8(ascii: "]"))
        case .object(let o):
            out.append(UInt8(ascii: "{"))
            let keys = o.keys.map { (key: $0, utf8: Array($0.utf8)) }.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
            for (i, k) in keys.enumerated() {
                if i > 0 { out.append(UInt8(ascii: ",")) }
                writeString(k.key, &out)
                out.append(UInt8(ascii: ":"))
                write(o[k.key]!, &out)
            }
            out.append(UInt8(ascii: "}"))
        }
    }

    static func writeString(_ s: String, _ out: inout [UInt8]) {
        out.append(UInt8(ascii: "\""))
        for b in s.utf8 {
            switch b {
            case UInt8(ascii: "\""): out += [UInt8(ascii: "\\"), UInt8(ascii: "\"")]
            case UInt8(ascii: "\\"): out += [UInt8(ascii: "\\"), UInt8(ascii: "\\")]
            case 0x0A: out += [UInt8(ascii: "\\"), UInt8(ascii: "n")]
            case 0x0D: out += [UInt8(ascii: "\\"), UInt8(ascii: "r")]
            case 0x09: out += [UInt8(ascii: "\\"), UInt8(ascii: "t")]
            case 0..<0x20:
                let hex = Array("0123456789abcdef".utf8)
                out += Array("\\u00".utf8) + [hex[Int(b >> 4)], hex[Int(b & 0xF)]]
            default: out.append(b)
            }
        }
        out.append(UInt8(ascii: "\""))
    }
}

// MARK: - 並べ直しの印

/// 要素の順に意味が無い集まり(Set)。
protocol CanonicalUnordered {}
extension Set: CanonicalUnordered {}

/// 辞書(キーが文字列でないと [キー, 値…] の配列になる)。
protocol CanonicalDictionary {}
extension Dictionary: CanonicalDictionary {}

// MARK: - Encoder → Value の木

enum ValueEncoding {
    /// 書きかけの節。
    final class Box {
        enum Content {
            case empty
            case single(Value)
            case object([String: Box])
            case array([Box])
        }

        var content: Content = .empty

        func asObject() -> [String: Box] {
            if case .object(let o) = content { return o }
            content = .object([:])
            return [:]
        }

        func asArray() -> [Box] {
            if case .array(let a) = content { return a }
            content = .array([])
            return []
        }

        func set(_ key: String, _ child: Box) {
            var o = asObject()
            o[key] = child
            content = .object(o)
        }

        func append(_ child: Box) {
            var a = asArray()
            a.append(child)
            content = .array(a)
        }

        func finish() -> Value {
            switch content {
            case .empty: .object([:])
            case .single(let v): v
            case .object(let o): .object(o.mapValues { $0.finish() })
            case .array(let a): .array(a.map { $0.finish() })
            }
        }
    }

    static func box<T: Encodable>(_ value: T, path: [CodingKey]) throws -> Box {
        let b = Box()
        try value.encode(to: Enc(box: b, codingPath: path))
        if value is CanonicalUnordered, case .array(let a) = b.content {
            b.content = .single(.array(a.map { $0.finish() }.sorted(by: canonicalLess)))
        } else if value is CanonicalDictionary, case .array(let a) = b.content, a.count % 2 == 0 {
            // [キー, 値, キー, 値…] → キーの正準のバイト列の順
            var pairs: [(key: Value, value: Value, bytes: [UInt8])] = []
            for i in stride(from: 0, to: a.count, by: 2) {
                let k = a[i].finish()
                pairs.append((k, a[i + 1].finish(), CanonicalJSON.bytes(k)))
            }
            pairs.sort { $0.bytes.lexicographicallyPrecedes($1.bytes) }
            b.content = .single(.array(pairs.flatMap { [$0.key, $0.value] }))
        }
        return b
    }

    static func canonicalLess(_ a: Value, _ b: Value) -> Bool {
        CanonicalJSON.bytes(a).lexicographicallyPrecedes(CanonicalJSON.bytes(b))
    }

    static func primitive<T: Encodable>(_ value: T) -> Value? {
        switch value {
        case let v as Bool: .bool(v)
        case let v as String: .string(v)
        case let v as Int: .int(Int64(v))
        case let v as Int8: .int(Int64(v))
        case let v as Int16: .int(Int64(v))
        case let v as Int32: .int(Int64(v))
        case let v as Int64: .int(v)
        case let v as UInt: v <= UInt(Int64.max) ? .int(Int64(v)) : .uint(UInt64(v))
        case let v as UInt8: .int(Int64(v))
        case let v as UInt16: .int(Int64(v))
        case let v as UInt32: .int(Int64(v))
        case let v as UInt64: v <= UInt64(Int64.max) ? .int(Int64(v)) : .uint(v)
        default: nil
        }
    }

    static func floatError(_ path: [CodingKey], _ v: Any) -> EncodingError {
        EncodingError.invalidValue(v, .init(codingPath: path,
                                            debugDescription: "保存に浮動小数は入れない(Milli・Purity の整数で持つ)"))
    }

    struct Enc: Encoder {
        let box: Box
        var codingPath: [CodingKey]
        var userInfo: [CodingUserInfoKey: Any] { [:] }

        func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
            _ = box.asObject()
            return KeyedEncodingContainer(Keyed<Key>(box: box, codingPath: codingPath))
        }

        func unkeyedContainer() -> UnkeyedEncodingContainer {
            _ = box.asArray()
            return Unkeyed(box: box, codingPath: codingPath)
        }

        func singleValueContainer() -> SingleValueEncodingContainer { Single(box: box, codingPath: codingPath) }
    }

    struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init(stringValue: String) { self.stringValue = stringValue }
        init(intValue: Int) { self.stringValue = String(intValue); self.intValue = intValue }
    }

    struct Keyed<Key: CodingKey>: KeyedEncodingContainerProtocol {
        let box: Box
        var codingPath: [CodingKey]

        func put(_ v: Value, _ key: Key) {
            let b = Box()
            b.content = .single(v)
            box.set(key.stringValue, b)
        }

        mutating func encodeNil(forKey key: Key) throws { put(.null, key) }
        mutating func encode(_ value: Double, forKey key: Key) throws { throw floatError(codingPath + [key], value) }
        mutating func encode(_ value: Float, forKey key: Key) throws { throw floatError(codingPath + [key], value) }

        mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
            if let p = primitive(value) { return put(p, key) }
            box.set(key.stringValue, try ValueEncoding.box(value, path: codingPath + [key]))
        }

        mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type, forKey key: Key)
            -> KeyedEncodingContainer<NestedKey>
        {
            let b = Box()
            _ = b.asObject()
            box.set(key.stringValue, b)
            return KeyedEncodingContainer(Keyed<NestedKey>(box: b, codingPath: codingPath + [key]))
        }

        mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
            let b = Box()
            _ = b.asArray()
            box.set(key.stringValue, b)
            return Unkeyed(box: b, codingPath: codingPath + [key])
        }

        mutating func superEncoder() -> Encoder { superEncoder(forKey: Key(stringValue: "super")!) }

        mutating func superEncoder(forKey key: Key) -> Encoder {
            let b = Box()
            box.set(key.stringValue, b)
            return Enc(box: b, codingPath: codingPath + [key])
        }
    }

    struct Unkeyed: UnkeyedEncodingContainer {
        let box: Box
        var codingPath: [CodingKey]
        var count: Int { if case .array(let a) = box.content { a.count } else { 0 } }

        func put(_ v: Value) {
            let b = Box()
            b.content = .single(v)
            box.append(b)
        }

        var nextPath: [CodingKey] { codingPath + [AnyKey(intValue: count)] }

        mutating func encodeNil() throws { put(.null) }
        mutating func encode(_ value: Double) throws { throw floatError(nextPath, value) }
        mutating func encode(_ value: Float) throws { throw floatError(nextPath, value) }

        mutating func encode<T: Encodable>(_ value: T) throws {
            if let p = primitive(value) { return put(p) }
            box.append(try ValueEncoding.box(value, path: nextPath))
        }

        mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type)
            -> KeyedEncodingContainer<NestedKey>
        {
            let path = nextPath
            let b = Box()
            _ = b.asObject()
            box.append(b)
            return KeyedEncodingContainer(Keyed<NestedKey>(box: b, codingPath: path))
        }

        mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
            let path = nextPath
            let b = Box()
            _ = b.asArray()
            box.append(b)
            return Unkeyed(box: b, codingPath: path)
        }

        mutating func superEncoder() -> Encoder {
            let path = nextPath
            let b = Box()
            box.append(b)
            return Enc(box: b, codingPath: path)
        }
    }

    struct Single: SingleValueEncodingContainer {
        let box: Box
        var codingPath: [CodingKey]

        mutating func encodeNil() throws { box.content = .single(.null) }
        mutating func encode(_ value: Double) throws { throw floatError(codingPath, value) }
        mutating func encode(_ value: Float) throws { throw floatError(codingPath, value) }

        mutating func encode<T: Encodable>(_ value: T) throws {
            if let p = primitive(value) {
                box.content = .single(p)
                return
            }
            box.content = try ValueEncoding.box(value, path: codingPath).content
        }
    }
}
