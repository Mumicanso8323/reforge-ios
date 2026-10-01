import RFKernel

// 研究・スキル・力の定義の補助(持ち主: U10)。定義の本体は Defs.swift の ResearchDef・SkillDef・AbilityDef。
// 他のシステムは、ここの ContentDB の問い合わせで「スキル・力がその作業にどう効くか」を読む
// (RFResearch・RFAbilities は他のシステムから import できないので、純粋な問い合わせはコンテンツの層に置く)。

/// 人の作業への効き。スキル(SkillDef.modifiers)と力(AbilityDef.passives)が共通に使う。
public enum WorkModifier: Codable, Hashable, Sendable {
    /// 行為の成功率に足す(万分率)。火起こしの成功率など。
    case chance(interaction: InteractionID, basisPoints: Int)
    /// 作業の速さを千分率で掛ける。work は作業の名前(`WorkKey`)。
    case speed(work: String, permille: Int)
    /// 得られる量を千分率で掛ける。
    case yield(interaction: InteractionID, permille: Int)
    /// 道具なしで読める性質("purity" など)。検品台に付いたときの効き(BEAT-03・R2)。
    /// R1 では、これを人ごとに比べて見せる画面を作らない(REQ-S5)。
    case perceives(sense: String)
}

/// 作業の名前(WorkModifier.speed の work)。
public enum WorkKey {
    public static let research = "research"
    public static let build = "build"
    public static let guardArea = "guard"
    public static let haul = "haul"
    public static func module(_ k: ModuleKindID) -> String { "module:\(k.rawValue)" }
    public static func interaction(_ i: InteractionID) -> String { "interaction:\(i.rawValue)" }
    public static func handwork(_ h: HandworkID) -> String { "handwork:\(h.rawValue)" }
}

/// 力が持ち主のまわりに付ける範囲の効果。
public struct AbilityAura: Codable, Equatable, Sendable {
    public var kind: AuraKindID
    public var radius: Int

    public init(kind: AuraKindID, radius: Int) {
        self.kind = kind
        self.radius = radius
    }
}

/// 力の代償(原作の新しい系統: 力の元を使い、足りなければ体で払う。危ない力は精神力も、禁じ手は恒久の代償)。
public struct AbilityCost: Codable, Equatable, Sendable {
    /// 力の元(整数。AbilityDef.reserveMax の単位)。足りない分は 1 につき healthPerShortfall の傷になる。
    public var reserve: Int?
    /// 足りない力の元 1 あたりの傷(既定 5)。
    public var healthPerShortfall: Int?
    /// 精神力(体の持ち主 U4 へのコマンドが R3 で入るまでは来歴の detail に残すだけ)。
    public var mind: Int?
    /// 傷(使うたびに必ず)。
    public var health: Int?
    /// 触媒として使う物(拠点の蓄え → 使う人の持ち物の順に取る)。
    public var items: [Ingredient]?

    public init(reserve: Int? = nil, healthPerShortfall: Int? = nil, mind: Int? = nil, health: Int? = nil,
                items: [Ingredient]? = nil) {
        self.reserve = reserve
        self.healthPerShortfall = healthPerShortfall
        self.mind = mind
        self.health = health
        self.items = items
    }
}

extension ResearchDef {
    /// 必要な点の合計(段があれば段の合計)。
    public var totalPoints: Int {
        if let n = nodes, !n.isEmpty { return n.reduce(0) { $0 + max(0, $1.points) } }
        return max(0, points)
    }

    /// 進む時間帯(既定は昼だけ)。
    public var activePhases: [DayPhase] { phases ?? [.day] }
}

extension ContentDB {
    /// 研究の建造物の進む速さ(1 ゲーム時間あたりの点。provides["research"])。研究の建造物でなければ 0。
    public func researchRate(of kind: StructureKindID) -> Int {
        max(0, structures[kind]?.provides["research"] ?? 0)
    }

    /// その人に効く作業の効き(身につけたスキル + 生まれつきの力)。順番は決定的(スキル ID 順 → 力 ID 順)。
    public func workModifiers(person: PersonID, skills: Set<SkillID>) -> [WorkModifier] {
        var out: [WorkModifier] = []
        for s in skills.sorted() { out += self.skills[s]?.modifiers ?? [] }
        for a in abilities.keys.sorted() where abilities[a]?.holders?.contains(person) == true {
            out += abilities[a]?.passives ?? []
        }
        return out
    }

    /// 行為の成功率に足す万分率(火起こしなど)。
    public func chanceBonus(person: PersonID, skills: Set<SkillID>, interaction: InteractionID) -> Int {
        workModifiers(person: person, skills: skills).reduce(0) { acc, m in
            if case .chance(let i, let bp) = m, i == interaction { return acc + bp }
            return acc
        }
    }

    /// 作業の速さ(千分率。効きを掛け合わせる。効きが無ければ 1000)。
    public func speedPermille(person: PersonID, skills: Set<SkillID>, work: String) -> Int {
        workModifiers(person: person, skills: skills).reduce(1000) { acc, m in
            if case .speed(let w, let p) = m, w == work { return acc * max(0, p) / 1000 }
            return acc
        }
    }

    /// 得られる量(千分率)。
    public func yieldPermille(person: PersonID, skills: Set<SkillID>, interaction: InteractionID) -> Int {
        workModifiers(person: person, skills: skills).reduce(1000) { acc, m in
            if case .yield(let i, let p) = m, i == interaction { return acc * max(0, p) / 1000 }
            return acc
        }
    }

    /// 道具なしで読める性質があるか(検品台など。BEAT-03)。
    public func perceives(person: PersonID, skills: Set<SkillID>, sense: String) -> Bool {
        workModifiers(person: person, skills: skills).contains { $0 == .perceives(sense: sense) }
    }

    /// 研究・スキルで解禁される物(始まりの解禁を除く)。ここに入る物は、解禁されるまで使えない、という読み方ができる
    /// (モジュールは始まりの解禁で使えるものを決めているので、建造物・手作業・行為の担当が同じ読み方をするときに使う)。
    public var gatedUnlocks: Set<UnlockTarget> {
        var s = Set<UnlockTarget>()
        for r in research.values {
            s.formUnion(r.unlocks)
            for n in r.nodes ?? [] { s.formUnion(n.unlocks ?? []) }
        }
        for k in skills.values { s.formUnion(k.unlocks ?? []) }
        s.subtract(start.unlocks)
        return s
    }
}
