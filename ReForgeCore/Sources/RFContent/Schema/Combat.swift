import RFKernel

// 脅威と戦闘の定義(CORE-11)。持ち主: U9(RFCombat)。
// 名前は持たない(敵の名前は認識の表の見出し "enemy:<id>" から引く。いまの呼び方と後の呼び方は事実で切り替わる)。
// 数値は整数。体力・攻撃・守り・速さは原作 Combat/Enemy.cs の単位(人の体力 100 と同じ物差し)。

/// 敵 1 種。省略した項目は既定値(R1 の小型の獣)。
public struct EnemyDef: ContentDef, Equatable {
    public var id: EnemyKindID
    /// 1 体の体力(原作 MaxHP)。
    public var health: Int
    /// 1 体の攻撃(原作 Attack)。
    public var attack: Int
    /// 倒したときに得られる物(1 体ごとに引く。確率は万分率)。
    public var drops: [Yield]
    public var parameters: Value?

    /// 守り(原作 Defense)。既定 0。
    public var defense: Int?
    /// 速さ(原作 Speed。帯の上の手番の順・命中・1 手で動けるマス = 速さ / 2)。既定 5。
    public var speed: Int?
    /// 間合い(帯のマス)。既定 0...0(同じマスで噛む)。
    public var reachMin: Int?
    public var reachMax: Int?
    /// 地図の上の速さ(マス毎時)。既定 4。
    public var mapSpeed: Int?
    /// 夜だけ出て、夜明けに帰る。既定 true。
    public var nocturnal: Bool?
    /// この獣の巣になる POI の種類(地図の POI)。巣から夜に出てくる。巣に近づくと守りが出る。
    public var nests: [POIKindID]?
    /// 巣に近づいたときに出る守りの数。既定 2。
    public var nestGuard: Int?
    /// 夜に蓄えを狙って来る規則(nil なら来ない)。
    public var raid: RaidDef?
    /// 昼に出会う地形(森の近道など)と、その地形にいる人 1 人が 1 時間に出会う確率(万分率)。
    public var habitats: [TerrainID]?
    public var encounterPerHour: Int?
    /// 出会ったときの数。既定 1...1。
    public var encounterMin: Int?
    public var encounterMax: Int?
    /// 出会いはこの事実を知ってから起きる(日数でなく、プレイヤーが知ったことで始まる)。
    public var encounterRequiresFact: FactExpr?
    /// この事実を知ったら出会わなくなる。
    public var encounterUntilFact: FactExpr?
    /// 事実ごとの出会いの率の増減(例: 獣の行動の記録を読んだら下がる)。
    public var encounterFactModifiers: [FactRateModifier]?
    /// 負けたときに奪われる物(拠点の蓄えから。足りなければある分だけ)。
    public var steals: [Ingredient]?
    /// 倒した記録に付ける印(狩り・倒した相手を後で指す)。
    public var tags: [ProvenanceTag]?
    /// 巣を壊した記録に付ける印。
    public var nestTags: [ProvenanceTag]?
    /// 帯の長さ(大きい敵・ボスは 8・10。R3)。既定は CombatDef.laneSize。
    public var laneSize: Int?
    /// 倒した数 1 あたりの強さの上積み(千分率。原作 Enemy.Scale は 10 = 1%)。R1 は 0。
    public var growthPerKill: Int?

    public init(id: EnemyKindID, health: Int, attack: Int, drops: [Yield] = [], parameters: Value? = nil,
                defense: Int? = nil, speed: Int? = nil, reachMin: Int? = nil, reachMax: Int? = nil,
                mapSpeed: Int? = nil, nocturnal: Bool? = nil, nests: [POIKindID]? = nil, nestGuard: Int? = nil,
                raid: RaidDef? = nil, habitats: [TerrainID]? = nil, encounterPerHour: Int? = nil,
                encounterMin: Int? = nil, encounterMax: Int? = nil, encounterRequiresFact: FactExpr? = nil,
                encounterUntilFact: FactExpr? = nil, encounterFactModifiers: [FactRateModifier]? = nil,
                steals: [Ingredient]? = nil,
                tags: [ProvenanceTag]? = nil, nestTags: [ProvenanceTag]? = nil, laneSize: Int? = nil,
                growthPerKill: Int? = nil) {
        self.id = id
        self.health = health
        self.attack = attack
        self.drops = drops
        self.parameters = parameters
        self.defense = defense
        self.speed = speed
        self.reachMin = reachMin
        self.reachMax = reachMax
        self.mapSpeed = mapSpeed
        self.nocturnal = nocturnal
        self.nests = nests
        self.nestGuard = nestGuard
        self.raid = raid
        self.habitats = habitats
        self.encounterPerHour = encounterPerHour
        self.encounterMin = encounterMin
        self.encounterMax = encounterMax
        self.encounterRequiresFact = encounterRequiresFact
        self.encounterUntilFact = encounterUntilFact
        self.encounterFactModifiers = encounterFactModifiers
        self.steals = steals
        self.tags = tags
        self.nestTags = nestTags
        self.laneSize = laneSize
        self.growthPerKill = growthPerKill
    }
}

/// 夜に蓄えを狙って来る規則。
public struct RaidDef: Codable, Equatable, Sendable {
    /// 一晩に来る確率(万分率)。
    public var perNight: Int
    /// 何日目から来るか。既定 1。日数の引き金は使わない方針(結合設計 §3.1)なので、新しいコンテンツは requiresFact で書く。
    public var fromDay: Int?
    /// 群れの数。既定 1...1。
    public var min: Int?
    public var max: Int?
    /// 巣が無いと来ない(巣を壊せば来なくなる)。既定 false(灯りの外の遠くから来る)。
    public var requiresNest: Bool?
    /// 見つけた巣(knowledge.discovered に入った POI)からだけ来る。見つける前は来ない。既定 false。
    public var requiresKnownNest: Bool?
    /// この事実を知ってから来る(例: 最初の脅威の出来事のあと)。
    public var requiresFact: FactExpr?
    /// この事実を知ったら来なくなる。
    public var untilFact: FactExpr?
    /// 事実ごとの率の増減。
    public var factModifiers: [FactRateModifier]?
    /// 獣が寄る 3 つの入力(煙・縄張り・闇。序盤の設計 W-02c)。nil なら率は perNight のまま。持ち主: U21
    public var lure: RaidLureDef?

    public init(perNight: Int, fromDay: Int? = nil, min: Int? = nil, max: Int? = nil, requiresNest: Bool? = nil,
                requiresKnownNest: Bool? = nil, requiresFact: FactExpr? = nil, untilFact: FactExpr? = nil,
                factModifiers: [FactRateModifier]? = nil, lure: RaidLureDef? = nil) {
        self.lure = lure
        self.perNight = perNight
        self.fromDay = fromDay
        self.min = min
        self.max = max
        self.requiresNest = requiresNest
        self.requiresKnownNest = requiresKnownNest
        self.requiresFact = requiresFact
        self.untilFact = untilFact
        self.factModifiers = factModifiers
    }
}

/// 獣が寄る入力の重み(どれも万分率で一晩の率に足す。省略は 0)。持ち主: U21
public struct RaidLureDef: Codable, Equatable, Sendable {
    /// 煙: 日没に燃えている火床 1 つあたり。
    public var smoke: Int?
    /// 縄張り: その獣の巣から territoryRadius マス以内にある置いた物(伐採の跡地の作業場・音の出る装置)1 つあたり。
    public var territory: Int?
    public var territoryRadius: Int?
    /// 闇: 日没に焚き火が 1 つも燃えていないとき。夜のうちに火が消えたときも、この重みでもう一度だけ寄るかを振る。
    public var dark: Int?
    /// しきい値(序盤の設計 v0.4: 合計 6 以上の夜に寄る)。あれば確率で振らず、重みの合計がこれ以上の夜に必ず寄る
    /// (perNight と factModifiers は使わない。requiresFact・untilFact は効く)。一晩に 1 回まで。
    public var threshold: Int?

    public init(smoke: Int? = nil, territory: Int? = nil, territoryRadius: Int? = nil, dark: Int? = nil,
                threshold: Int? = nil) {
        self.threshold = threshold
        self.smoke = smoke
        self.territory = territory
        self.territoryRadius = territoryRadius
        self.dark = dark
    }
}

/// 事実による率の増減(万分率の率に)。知っている事実の式が成り立てば、permille を掛けてから add を足す。
public struct FactRateModifier: Codable, Equatable, Sendable {
    public var fact: FactExpr
    /// 足す量(万分率。負で下がる)。
    public var add: Int?
    /// 掛ける量(千分率。500 = 半分)。
    public var permille: Int?

    public init(fact: FactExpr, add: Int? = nil, permille: Int? = nil) {
        self.fact = fact
        self.add = add
        self.permille = permille
    }
}

/// 事実で決まる率(日数を使わない引き金。結合設計 §3.1)。
public enum FactRate {
    /// requires が成り立たない・until が成り立つなら 0。そうでなければ base に modifiers を順に当てる(0 未満は 0)。
    public static func rate(_ base: Int, requires: FactExpr?, until: FactExpr?, modifiers: [FactRateModifier]?,
                            known: Set<FactID>) -> Int {
        if let r = requires, !r.evaluate(known) { return 0 }
        if let u = until, u.evaluate(known) { return 0 }
        var v = base
        for m in modifiers ?? [] where m.fact.evaluate(known) {
            if let p = m.permille { v = v * p / 1000 }
            if let a = m.add { v += a }
        }
        return max(0, v)
    }
}

/// 戦闘の規則(単一の設定。後の層が勝つ)。nil の項目は R1 の既定値。
public struct CombatDef: Codable, Equatable, Sendable {
    /// 帯の長さ(雑魚戦 6。原作 BattleField.DetermineSize)。
    public var laneSize: Int?
    /// 1 手番のゲーム秒。昼は実時間で見えるので、方針・撤退を選べる長さにする。既定 120(約 0.7 実秒)。
    public var turnSeconds: Int?
    /// 人の素の強さ(全員に共通。ノアだけを強くしない)。
    public var personAttack: Int?
    public var personDefense: Int?
    public var personSpeed: Int?
    /// 人はこの体力(整数)を下回ると倒れて帯から外れる。既定 40。
    public var downBelow: Int?
    /// 装備の枠の名前。既定 "weapon"。
    public var weaponSlot: String?
    /// 武器の上積み = 硬さ(0〜100)× 純度 × 純度の効き ÷ この値。既定 5。
    public var weaponDivisor: Int?
    /// 物の形 → 間合い(帯のマス)。無い形は 0...0(殴る)。既定: 棒 1...2(槍)・板 0...1(刃)。
    public var reachByShape: [String: ReachDef]?
    /// 前に出たときの与える傷・受ける傷(千分率)。既定 1250・1100。
    public var advanceDealtPermille: Int?
    public var advanceTakenPermille: Int?
    /// 撤退の成功の基礎(百分率)。既定 50。
    public var retreatBase: Int?
    /// 人に寄るマス(チェビシェフ)。既定 1。
    public var engageRadius: Int?
    /// 蓄えに着いた獣に、拠点の人が駆けつける半径。既定 6。
    public var rallyRadius: Int?
    /// 戦闘の場所からこの半径の獣・仲間は同じ戦闘に加わる。既定 2。
    public var joinRadius: Int?
    /// 巣の無い獣が出てくる、蓄えからの距離。既定 14。
    public var approachDistance: Int?
    /// 夜の獣がこの距離より遠い巣からは来ない。既定 48。
    public var nestRange: Int?
    /// 日没から何時間後に来るか(この範囲で引く)。既定 1...8。
    public var raidHoursMin: Int?
    public var raidHoursMax: Int?
    /// 負けたり逃げられたりした後、獣が人に寄らない時間。既定 1。
    public var calmHours: Int?

    public init() {}

    public var lane: Int { laneSize ?? 6 }
    public var turn: Int64 { Int64(turnSeconds ?? 120) }
    public var attack: Int { personAttack ?? 4 }
    public var defense: Int { personDefense ?? 0 }
    public var speed: Int { personSpeed ?? 6 }
    public var down: Int { downBelow ?? 40 }
    public var slot: String { weaponSlot ?? "weapon" }
    public var divisor: Int { max(1, weaponDivisor ?? 5) }
    public var reach: [String: ReachDef] {
        reachByShape ?? ["rod": ReachDef(min: 1, max: 2), "pipe": ReachDef(min: 1, max: 2),
                         "plate": ReachDef(min: 0, max: 1), "thin_plate": ReachDef(min: 0, max: 1),
                         "thick_plate": ReachDef(min: 0, max: 1)]
    }
    public var advanceDealt: Int { advanceDealtPermille ?? 1250 }
    public var advanceTaken: Int { advanceTakenPermille ?? 1100 }
    public var retreat: Int { retreatBase ?? 50 }
    public var engage: Int { engageRadius ?? 1 }
    public var rally: Int { rallyRadius ?? 6 }
    public var join: Int { joinRadius ?? 2 }
    public var approach: Int { approachDistance ?? 14 }
    public var nestReach: Int { nestRange ?? 48 }
    public var raidHours: ClosedRange<Int> {
        let lo = max(0, raidHoursMin ?? 1)
        return lo...max(lo, raidHoursMax ?? 8)
    }
    public var calm: Int { calmHours ?? 1 }
}

/// 間合い(帯のマス)。
public struct ReachDef: Codable, Equatable, Sendable {
    public var min: Int
    public var max: Int

    public init(min: Int, max: Int) {
        self.min = min
        self.max = max
    }
}
