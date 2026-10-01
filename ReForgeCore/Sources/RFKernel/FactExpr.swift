/// 事実の集合だけで決まる条件式。認識の層(名前の切り替え)・禁止語の規則・事実の解禁で使う。
/// 世界の状態(在庫・仲間…)を見る条件は RFContent の Condition(こちらを含む)。
///
/// JSON の形(短く書けるように):
///   "fact.x"                         → .fact
///   {"all": [...]} / {"any": [...]} / {"not": ...}
///   true                             → .always
public indirect enum FactExpr: Hashable, Sendable {
    case always
    case fact(FactID)
    case all([FactExpr])
    case any([FactExpr])
    case not(FactExpr)

    public func evaluate(_ known: Set<FactID>) -> Bool {
        switch self {
        case .always: true
        case .fact(let f): known.contains(f)
        case .all(let xs): xs.allSatisfy { $0.evaluate(known) }
        case .any(let xs): xs.contains { $0.evaluate(known) }
        case .not(let x): !x.evaluate(known)
        }
    }

    /// 式に出てくる事実(検証・禁止語の監査で、どの事実の組み合わせを試すか決めるのに使う)。
    public var mentionedFacts: Set<FactID> {
        switch self {
        case .always: []
        case .fact(let f): [f]
        case .all(let xs), .any(let xs): xs.reduce(into: Set()) { $0.formUnion($1.mentionedFacts) }
        case .not(let x): x.mentionedFacts
        }
    }
}

extension FactExpr: Codable {
    private enum Keys: String, CodingKey { case all, any, not }

    public init(from decoder: Decoder) throws {
        if let c = try? decoder.singleValueContainer() {
            if let b = try? c.decode(Bool.self) {
                self = b ? .always : .not(.always)
                return
            }
            if let s = try? c.decode(String.self) {
                self = .fact(FactID(s))
                return
            }
        }
        let k = try decoder.container(keyedBy: Keys.self)
        if let xs = try k.decodeIfPresent([FactExpr].self, forKey: .all) { self = .all(xs); return }
        if let xs = try k.decodeIfPresent([FactExpr].self, forKey: .any) { self = .any(xs); return }
        if let x = try k.decodeIfPresent(FactExpr.self, forKey: .not) { self = .not(x); return }
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "FactExpr の形が不明"))
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .always:
            var c = encoder.singleValueContainer()
            try c.encode(true)
        case .fact(let f):
            var c = encoder.singleValueContainer()
            try c.encode(f.raw)
        case .all(let xs):
            var k = encoder.container(keyedBy: Keys.self)
            try k.encode(xs, forKey: .all)
        case .any(let xs):
            var k = encoder.container(keyedBy: Keys.self)
            try k.encode(xs, forKey: .any)
        case .not(let x):
            var k = encoder.container(keyedBy: Keys.self)
            try k.encode(x, forKey: .not)
        }
    }
}
