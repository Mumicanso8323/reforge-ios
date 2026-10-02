/// 火床の段(序盤の設計 §3.2)。数が大きいほど強く燃えている。
/// 定義(RFContent の HearthDef)と出来事(RFWorld の DomainEvent)の両方から見えるよう、ここに置く。持ち主: U21
public enum HearthLevel: Int, Codable, Hashable, Comparable, Sendable, CaseIterable {
    case out = 0, smoldering, flickering, burning, roaring

    public static func < (a: HearthLevel, b: HearthLevel) -> Bool { a.rawValue < b.rawValue }
}
