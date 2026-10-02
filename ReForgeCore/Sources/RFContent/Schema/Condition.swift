import RFKernel
import RFMatter

/// 世界の状態を見る条件(出来事の引き金・選択肢の出る条件・研究の前提・目標の達成・失敗の規則・一言の選び方…)。
/// 宣言的なデータで、評価は RFRules.ConditionEvaluator。
///
/// JSON は Swift の列挙の既定の形(case 名がキー、ラベルが中のキー)。例:
///   {"all": {"of": [ {"known": {"expr": "fact.x"}}, {"has": {"what": {"item": "wood", "quantity": 3}}} ]}}
///   {"ledger": {"query": {"act": "placed", "module": "furnace"}, "atLeast": 1}}
/// 省略可能(`?`)なラベルは JSON で書かなくてよい。
///
/// 引き金は日数でなく、工業の行為(初めて作った・建てた・配属した・解体した・観測した = firstTime / trigger / ledger)・
/// 世界の状態・前の出来事(eventFired / sinceFired)・追跡カウンタ(counter。TrackerDef が数える)・来歴で書く。
/// 「日数」で引く条件(dayAtLeast)は持っているが、物語の引き金には使わない(検証で警告する)。
public indirect enum Condition: Codable, Hashable, Sendable {
    case always
    case all(of: [Condition])
    case any(of: [Condition])
    case not(that: Condition)

    /// 知っている事実(認識の層と同じ式)。時代の区切りも事実の 1 つ。
    case known(expr: FactExpr)
    /// 物を持っている(拠点の蓄え+ノアの持ち物)。quantity 個以上。
    case has(what: Ingredient)
    /// 物の数を比べる(拠点の蓄え+ノアの持ち物)。what.quantity が比べる値。
    /// perMember = true なら「一員の人数 × quantity」と比べる(一人あたりの備え)。
    case stock(of: Ingredient, cmp: Comparison, perMember: Bool? = nil)
    /// モジュール・建造物が置かれている数。既定は建て終わった物だけ(建造中は数えない。リーダー決定)。
    /// includeUnfinished = true なら建造中も数える。
    case placedCount(module: ModuleKindID?, structure: StructureKindID?, atLeast: Int, includeUnfinished: Bool? = nil)
    /// 来歴の問い合わせ(「炉を置いたことがある」「この印の付いた物を 10 個以上作った」)。
    case ledger(query: ProvenanceQuery, atLeast: Int)
    /// 「工業の初めて」: 引き金になった記録が、この問い合わせに合う最初の記録である。
    case firstTime(query: ProvenanceQuery)
    /// 引き金になった記録がこの問い合わせに合う(初めてでなくてよい)。
    case trigger(query: ProvenanceQuery)
    /// 有限の部品の状態(ある区画を解体したか、など)。
    case part(poiKind: POIKindID, part: String, state: PartStateName)
    /// POI の進み(漁った回数・印・部品の状態の数)。その種類の POI のどれか 1 つが合えば成り立つ。
    case poi(kind: POIKindID, test: POITest)
    /// 範囲の効果の中にいる。
    case inAura(person: PersonID, kind: AuraKindID)
    /// 人の状態。
    case person(id: PersonID, test: PersonTest)
    /// 条件(全部)に合う人が atLeast 人(既定 1)以上いる。既定は一員だけを数える。
    case someone(where: [PersonTest], atLeast: Int? = nil, includeNonMembers: Bool? = nil)
    /// 一員の人数。
    case members(atLeast: Int)
    /// 拠点の外の集団との関係。
    case group(id: GroupID, relationAtLeast: Int)
    /// 拠点の外の集団の印(コンテンツの ID 文字列)。
    case groupFlag(id: GroupID, flag: String)
    case counter(id: CounterID, cmp: Comparison, value: Int)
    /// 数値(千分率)。
    case stat(id: StatID, cmp: Comparison, value: Int)
    case phase(is: DayPhase)
    /// 日数(物語の引き金には使わない。仕組みの都合のときだけ)。
    case dayAtLeast(day: Int)
    case eventFired(id: EventID)
    /// 出来事が最後に起きてから hours ゲーム時間以上たった(起きていなければ成り立たない)。
    /// 「会ってから移動と準備の時間がたった」のような、行為の後の間合いに使う。
    case sinceFired(event: EventID, hours: Int)
    case choiceMade(event: EventID, choice: ChoiceID)
    case researchDone(id: ResearchID)
    case unlocked(target: UnlockTarget)
    /// ノア(または誰か)がある場所にいる。
    case at(person: PersonID, place: PlaceSelector)
    /// 場所の近く(チェビシェフ距離 radius 以内)に、この印の地形がある。印 "water" は TerrainDef.isWater の地形にも当たる。
    /// 例: 冷やす段の試作は水辺に接していればできる(radius 1)。
    case nearTerrain(place: PlaceSelector, tag: String, radius: Int)
    /// POI の種類を見つけている(atLeast 個以上。既定 1)。
    case discoveredPOI(kind: POIKindID, atLeast: Int? = nil)
    case objective(id: ObjectiveID, status: ObjectiveStatusName)
    /// 決定的な確率(物語の乱数の流れ)。万分率。
    case chance(basisPoints: Int)
    /// 何周目以降か(巻き戻しの後だけ起きる出来事)。
    case runAtLeast(index: Int)
    /// 工程表(記録・答え・工程表・選ぶ表)の進み(U15)。
    case sheet(id: SheetID, test: SheetTest)
    /// 拠点の段階が atLeast 以上(BaseDef.grades と拠点の段階の大きい方)。
    case baseGrade(atLeast: Int)
    /// どこかの火床(焚き火台・炉)がこの段以上で燃えている(U20。§2.7 の「火が燃えている以上」)。
    case hearthAtLeast(level: HearthLevel)
    /// 拠点の蓄えの品の数の合計が atLeast 以上(全品。§2.7 の「蓄えが 20 を超えた」)。
    case stockTotal(atLeast: Int)
    /// 実験ノートの所見が atLeast 件以上(§2.7 の「所見が 5 つ」)。
    case findings(atLeast: Int)
    /// この種類のマス(地形か POI。どちらか一方)を長押しで調べたことがある(§2.7 の「実のマスを調べた」)。
    case inspected(terrain: TerrainID?, poi: POIKindID?)
}

/// 目標の状態の名前(RFWorld の ObjectiveStatus と同じ値。RFContent は RFWorld に依存しないので写しを持つ)。
public enum ObjectiveStatusName: String, Codable, Hashable, Sendable { case active, done, failed }

/// 人についての条件。
public enum PersonTest: Codable, Hashable, Sendable {
    case member
    case alive
    case dead
    case met
    /// 一時的にいない(離脱・遠征)。
    case away
    case relationAtLeast(rank: Int)
    case ideologyAtLeast(axis: IdeologyAxisID, value: Int)
    case hasMemory(kind: MemoryKindID)
    case assignedToModule(kind: ModuleKindID?)
    case hasSkill(skill: SkillID)
    /// 体の数値(health・stamina・satiety・hydration・mind)を比べる。value は千分率の raw(30 = 30000)。
    case body(stat: String, cmp: Comparison, value: Int)
    /// 得意分野(PersonDef.specialties)。
    case specialty(tag: String)
    /// ある人から半径 radius マス以内にいる(同じ層)。
    case near(person: PersonID, radius: Int)
    /// いま働いている(モジュールに付いている・運んでいる・行為の途中)。
    case working
    /// 拠点の外の集団に属している(id が nil ならどれか)。
    case inGroup(id: GroupID?)
}

/// POI についての条件。
public enum POITest: Codable, Hashable, Sendable {
    /// 調べた・漁った回数。
    case visitsAtLeast(count: Int)
    /// 印(調べ尽くした・何かを取った、など。コンテンツの ID 文字列)。
    case flag(name: String)
    /// その状態の部品の数。
    case partsInState(state: PartStateName, atLeast: Int)
    /// 部品の修理の段階(POIProgress.repair。0 = 壊れたまま)が stage 以上(U19)。
    case repairAtLeast(part: String, stage: Int)
}

/// 工程表の進みの調べ方。
public enum SheetTest: Codable, Hashable, Sendable {
    /// 開いた(slot nil = 表そのもの / 番号 = その記録)。
    case opened(slot: Int?)
    /// 空いた席を開いた数。
    case emptySlotsSeen(atLeast: Int)
    /// 行に答えを置いた(query があれば、置いた来歴がそれに合う)。
    case answered(row: String, query: ProvenanceQuery?)
    /// 工程表で技能を付けた(person nil = 誰でも。atLeast 既定 1 人)。
    case granted(person: PersonID?, atLeast: Int?)
    /// 使わなかった(プレイヤーが使わないと決めたか、本人が断った)。
    case declined(person: PersonID?, atLeast: Int?)
    /// 含める人(person nil = 人数)。
    case included(person: PersonID?, atLeast: Int?)
    /// 含めない人。
    case excluded(person: PersonID?, atLeast: Int?)
    /// 選ぶ表を確定した。
    case locked
}

/// 来歴の問い合わせ。指定した項目だけで絞る(nil は問わない)。
public struct ProvenanceQuery: Codable, Hashable, Sendable {
    public var act: ActKind?
    public var actor: PersonID?
    public var item: ItemID?
    public var module: ModuleKindID?
    public var structure: StructureKindID?
    public var person: PersonID?
    public var enemy: EnemyKindID?
    public var poi: POIKindID?
    public var event: EventID?
    public var tag: ProvenanceTag?
    /// false なら、今の来歴に加えて前の周回で覚えておいた記録(RunState.pastLives)も数える(既定は今の来歴だけ。
    /// 巻き戻しの後も、夜明けより前の記録は今の来歴に残っている)。
    public var currentRunOnly: Bool?

    public init(act: ActKind? = nil, actor: PersonID? = nil, item: ItemID? = nil, module: ModuleKindID? = nil,
                structure: StructureKindID? = nil, person: PersonID? = nil, enemy: EnemyKindID? = nil,
                poi: POIKindID? = nil, event: EventID? = nil, tag: ProvenanceTag? = nil, currentRunOnly: Bool? = nil) {
        self.act = act
        self.actor = actor
        self.item = item
        self.module = module
        self.structure = structure
        self.person = person
        self.enemy = enemy
        self.poi = poi
        self.event = event
        self.tag = tag
        self.currentRunOnly = currentRunOnly
    }
}

/// 場所の指し方。
public enum PlaceSelector: Codable, Hashable, Sendable {
    /// 引き金の出来事の場所(来歴の place)。範囲の効果では、引き金が置いた物の記録ならその置いた物が中心になる。
    case trigger
    case person(id: PersonID)
    case poiKind(kind: POIKindID)
    case base
    case point(at: WorldPoint)
    /// 置いた物(その種類のうち最も早く置いたもの)。範囲の効果の中心にすると、置いた物と一緒に動き・消える。
    case placement(module: ModuleKindID?, structure: StructureKindID?)
    /// 半径つき。
    indirect case near(place: PlaceSelector, radius: Int)
}

/// 解禁の対象。
public enum UnlockTarget: Codable, Hashable, Sendable {
    case module(id: ModuleKindID)
    case structure(id: StructureKindID)
    case handwork(id: HandworkID)
    case interaction(id: InteractionID)
    case research(id: ResearchID)
}

// MARK: - 走査(検証と参照の確かめに使う)

extension Condition {
    /// この条件と、その中の条件を全部たどる(深さ優先・前順)。
    public func walk(_ visit: (Condition) -> Void) {
        visit(self)
        switch self {
        case .all(let xs), .any(let xs): for x in xs { x.walk(visit) }
        case .not(let x): x.walk(visit)
        default: break
        }
    }

    /// 中で参照している出来事。
    public var referencedEvents: [EventID] {
        var out: [EventID] = []
        walk { c in
            switch c {
            case .eventFired(let e), .sinceFired(let e, _), .choiceMade(let e, _): out.append(e)
            default: break
            }
        }
        return out
    }

    /// 日数を見ているか。
    public var usesDay: Bool {
        var found = false
        walk { if case .dayAtLeast = $0 { found = true } }
        return found
    }
}

// MARK: - 出来事まわりの検証(ContentValidator.validate から呼ぶ。持ち主: U11)

extension ContentValidator {
    static func narrativeRules(_ db: ContentDB, _ out: inout [Issue]) {
        sceneLineBudget(db, &out)
        narrativeReferencesExist(db, &out)
    }

    /// 場面は地図の上に 3 行まで(長い本文は資料の側に置く)。
    static func sceneLineBudget(_ db: ContentDB, _ out: inout [Issue]) {
        for (id, s) in db.scenes.sorted(by: { $0.key < $1.key }) where s.lines.count > 3 {
            out.append(Issue(level: .warning, rule: "scene.max-lines",
                             message: "\(id) は \(s.lines.count) 行(地図の上に出す文は 3 行まで)"))
        }
    }

    /// 出来事・場面・範囲の効果・目標の参照先が定義にある。
    static func narrativeReferencesExist(_ db: ContentDB, _ out: inout [Issue]) {
        func missing(_ what: String, _ id: String, _ origin: String) {
            out.append(Issue(level: .error, rule: "narrative.ref", message: "\(origin) が指す\(what) \(id) が無い"))
        }
        func checkCondition(_ c: Condition?, _ origin: String) {
            guard let c else { return }
            for e in c.referencedEvents where db.events[e] == nil { missing("出来事", e.rawValue, origin) }
            c.walk { x in
                if case .inAura(_, let k) = x, db.auras[k] == nil { missing("範囲の効果", k.rawValue, origin) }
                if case .sheet(let s, _) = x, db.sheets[s] == nil { missing("工程表", s.rawValue, origin) }
            }
        }
        func checkEffects(_ es: [Effect]?, _ origin: String) {
            for e in es ?? [] {
                switch e {
                case .startScene(let s): if db.scenes[s] == nil { missing("場面", s.rawValue, origin) }
                case .schedule(let ev, _), .fire(let ev), .unschedule(let ev):
                    if db.events[ev] == nil { missing("出来事", ev.rawValue, origin) }
                case .addAura(let k, _, _, _, _), .scaleAura(let k, _, _), .removeAura(let k):
                    if db.auras[k] == nil { missing("範囲の効果", k.rawValue, origin) }
                case .objective(let o, _): if db.objectives[o] == nil { missing("目標", o.rawValue, origin) }
                default: break
                }
            }
        }
        for (id, e) in db.events.sorted(by: { $0.key < $1.key }) {
            let o = "event \(id)"
            checkCondition(e.trigger.when, o)
            checkEffects(e.effects, o)
            if let s = e.scene, db.scenes[s] == nil { missing("場面", s.rawValue, o) }
            for ch in e.choices ?? [] {
                checkCondition(ch.when, "\(o) / \(ch.id)")
                checkEffects(ch.effects, "\(o) / \(ch.id)")
            }
        }
        for (id, ob) in db.objectives.sorted(by: { $0.key < $1.key }) {
            checkCondition(ob.completeWhen, "objective \(id)")
            checkCondition(ob.failWhen, "objective \(id)")
            checkEffects(ob.effects, "objective \(id)")
        }
        for (id, en) in db.endings.sorted(by: { $0.key < $1.key }) {
            checkCondition(en.when, "ending \(id)")
            checkEffects(en.effects, "ending \(id)")
        }
        for (id, l) in db.lines.sorted(by: { $0.key < $1.key }) {
            checkCondition(l.when, "line \(id)")
            if db.people[l.speaker] == nil { missing("人", l.speaker.rawValue, "line \(id)") }
        }
        for (id, d) in db.modules.sorted(by: { $0.key < $1.key }) {
            for k in d.auras ?? [] where db.auras[k] == nil { missing("範囲の効果", k.rawValue, "module \(id)") }
        }
        for (id, d) in db.structures.sorted(by: { $0.key < $1.key }) {
            for k in d.auras ?? [] where db.auras[k] == nil { missing("範囲の効果", k.rawValue, "structure \(id)") }
        }
        for (id, d) in db.people.sorted(by: { $0.key < $1.key }) {
            for k in d.auras ?? [] where db.auras[k] == nil { missing("範囲の効果", k.rawValue, "person \(id)") }
        }
        // 工程表(U15): 記録の席・答えの行・工程表・選ぶ表
        for (id, sh) in db.sheets.sorted(by: { $0.key < $1.key }) {
            let o = "sheet \(id)"
            checkCondition(sh.when, o)
            for r in sh.rows + (sh.entryRows ?? []) { checkCondition(r.when, o) }
            var rowIDs = Set<String>()
            for r in sh.rows {
                if r.answer != nil, r.id == nil {
                    out.append(Issue(level: .error, rule: "sheet.answer-id", message: "\(o) の答えの行に id が無い"))
                }
                if let rid = r.id, !rowIDs.insert(rid).inserted {
                    out.append(Issue(level: .error, rule: "sheet.row-id", message: "\(o) の行 \(rid) が重なっている"))
                }
            }
            var slots = Set<Int>()
            for e in sh.entries ?? [] {
                checkCondition(e.when, o)
                if let p = e.person, db.people[p] == nil { missing("人", p.rawValue, o) }
                if !slots.insert(e.slot).inserted || e.slot < 1 || e.slot > (sh.slots ?? Int.max) {
                    out.append(Issue(level: .error, rule: "sheet.slot", message: "\(o) の席 \(e.slot) が重なるか範囲の外"))
                }
            }
            if let im = sh.grant {
                checkCondition(im.when, o)
                for k in im.skills where db.skills[k] == nil { missing("技能", k.rawValue, o) }
            }
            if let m = sh.roster { checkCondition(m.when, o) }
        }
        for g in db.base.grades ?? [] { checkCondition(g.when, "base grade \(g.grade)") }
    }
}
