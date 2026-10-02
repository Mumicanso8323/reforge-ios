import RFKernel
import RFMap

/// 掘る規則(最上位キー "mining"。U19)。どれも省略でき、無ければどの鉱脈も刃の段を問わずに掘れる。
///
/// - 刃の段: blades を上から調べ、条件が成り立った段のうち最大のもの(どれも成り立たなければ 0)。
///   拠点全体の段(誰が掘っても同じ)。手で持つ道具を人ごとに数える仕組みは持たない。
/// - 硬さ: 鉱脈の種類ごとに要る刃の段。足りなければ理由つきで断る(「いまの道具では硬すぎる」)。
/// - 行為ごとの条件は InteractionDef.depositCategories・bladeTier(行為の側で足す)。
public struct MiningDef: Codable, Equatable, Sendable {
    public var blades: [BladeTier]?
    public var hardness: [DepositHardness]?
    /// 硬すぎて断るときの理由の文(既定 reason.mine.too_hard)。
    public var tooHard: TextID?

    public init(blades: [BladeTier]? = nil, hardness: [DepositHardness]? = nil, tooHard: TextID? = nil) {
        self.blades = blades
        self.hardness = hardness
        self.tooHard = tooHard
    }

    public static let tooHardDefault: TextID = "reason.mine.too_hard"

    /// その種類の鉱脈に要る刃の段(書いていなければ 0)。
    public func required(for category: DepositCategory) -> Int {
        (hardness ?? []).filter { $0.category == category }.map(\.tier).max() ?? 0
    }

    /// その種類の鉱脈の断りの理由。
    public func reason(for category: DepositCategory) -> TextID {
        (hardness ?? []).first { $0.category == category && $0.reason != nil }?.reason ?? tooHard ?? Self.tooHardDefault
    }
}

/// 刃の段 1 つ(条件が成り立てばこの段)。
public struct BladeTier: Codable, Equatable, Sendable {
    public var tier: Int
    public var when: Condition

    public init(tier: Int, when: Condition) {
        self.tier = tier
        self.when = when
    }
}

/// 鉱脈の種類ごとの硬さ。
public struct DepositHardness: Codable, Equatable, Sendable {
    public var category: DepositCategory
    /// 掘るのに要る刃の段。
    public var tier: Int
    /// この種類だけの断りの理由(無ければ MiningDef.tooHard)。
    public var reason: TextID?

    public init(category: DepositCategory, tier: Int, reason: TextID? = nil) {
        self.category = category
        self.tier = tier
        self.reason = reason
    }
}
