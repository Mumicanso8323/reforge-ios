import RFKernel
import RFMatter

/// システムが「起きたこと」を知らせる出来事。物語の出来事(EventDef)の引き金・仲間の反応・日誌・画面の知らせの元。
///
/// - 文章は持たない。ID と来歴だけ。
/// - record: この出来事に対応する来歴(あれば)。物語の効果はこれを inputs にして「何が引き金だったか」を残す。
/// - hook: コンテンツの EventDef.trigger.on に書く名前("crafted" など)。case を足したら hook も足す。
public enum DomainEvent: Codable, Equatable, Sendable {
    // 時間
    case phaseChanged(to: DayPhase, day: Int)
    case dawn(day: Int)
    // 知る
    case factLearned(fact: FactID, record: ProvenanceID?)
    case discovered(entity: EntityID, record: ProvenanceID)
    case tilesRevealed(layer: LayerID, count: Int)
    // 作る
    case trialed(record: ProvenanceID)
    case crafted(quantity: Int, record: ProvenanceID)
    case designed(design: EntityID, record: ProvenanceID)
    /// 推理の手がかり(HintDef)がノートに載った。from は仲間の知識なら仲間。
    case hintHeard(hint: HintID, from: PersonID?, record: ProvenanceID)
    case produced(placement: EntityID, quantity: Int)
    case moduleStopped(placement: EntityID, reason: TextID)
    case moduleResumed(placement: EntityID)
    // 置く・建てる
    case placed(placement: EntityID, record: ProvenanceID)
    case dismantled(placement: EntityID, record: ProvenanceID)
    case built(placement: EntityID, record: ProvenanceID)
    // 動く・探す
    case arrived(person: PersonID, at: WorldPoint)
    case walked(person: PersonID, tiles: Int, staminaCost: Int)
    case entered(person: PersonID, poi: EntityID)
    case interacted(person: PersonID, interaction: InteractionID, at: WorldPoint, record: ProvenanceID)
    case itemGained(holder: HolderID, stuff: Stuff, quantity: Int, record: ProvenanceID?)
    case itemSpent(holder: HolderID, stuff: Stuff, quantity: Int)
    case finiteUsed(record: ProvenanceID)
    /// 探索の出来事の表から 1 件起きた(event は ExploreEventDef の ID)。
    case explored(person: PersonID, event: EventID, record: ProvenanceID)
    /// 有限の部品の状態・修理の段階が変わった。
    case partChanged(poi: EntityID, part: String, record: ProvenanceID)
    // 人
    case personMet(person: PersonID, record: ProvenanceID)
    case personJoined(person: PersonID, record: ProvenanceID)
    case personLeft(person: PersonID, record: ProvenanceID)
    case personDied(person: PersonID, record: ProvenanceID)
    case relationChanged(person: PersonID, rank: Int, delta: Int)
    case opinion(person: PersonID, about: ProvenanceID, stance: Int)
    case memoryFormed(person: PersonID, kind: MemoryKindID)
    case assigned(person: PersonID, assignment: Assignment)
    // 生存
    case statCrossed(stat: StatID, value: Milli)
    case shortage(item: ItemID)
    case bodyChanged(person: PersonID)
    // 戦い
    case threatAppeared(threat: EntityID, kind: EnemyKindID)
    case battleStarted(battle: EntityID, record: ProvenanceID)
    case battleEnded(battle: EntityID, won: Bool, fled: Bool, record: ProvenanceID)
    /// 巣を壊した(poi は地図の実体)。
    case nestDestroyed(poi: EntityID, record: ProvenanceID)
    /// 獣に蓄えを奪われた。
    case raided(threat: EntityID, record: ProvenanceID)
    /// 罠(置いた物)が獣を倒した。
    case trapSprung(placement: EntityID, record: ProvenanceID)
    // 研究
    case researchCompleted(research: ResearchID, record: ProvenanceID)
    case skillAcquired(person: PersonID, skill: SkillID, record: ProvenanceID)
    case unlocked(what: String)
    /// 研究パッケージの中の段が終わった(node = 段の番号。0 から)。
    case researchNode(research: ResearchID, node: Int, record: ProvenanceID)
    // 力
    case abilityUsed(person: PersonID, ability: AbilityID, record: ProvenanceID)
    // 物語
    case eventFired(event: EventID, record: ProvenanceID)
    case decisionOpened(decision: EntityID, event: EventID)
    case decided(decision: EntityID, choice: ChoiceID, record: ProvenanceID)
    case sceneStarted(scene: SceneID)
    case objectiveChanged(objective: ObjectiveID, status: ObjectiveStatus)
    case chapterEnded(chapter: ChapterID, record: ProvenanceID)
    case endingReached(ending: EndingID)
    /// 仲間が一言いった(画面は認識の層で文字にして帯に出す)。
    case lineSpoken(person: PersonID, line: LineID)
    // 工程表(U15)
    case sheetOpened(sheet: SheetID, slot: Int?, empty: Bool, record: ProvenanceID)
    case answerPlaced(sheet: SheetID, row: String, record: ProvenanceID)
    case grantDeclined(sheet: SheetID, person: PersonID, refused: Bool, record: ProvenanceID)
    case rosterDeclared(sheet: SheetID, person: PersonID, included: Bool, record: ProvenanceID)
    case rosterConfirmed(sheet: SheetID, record: ProvenanceID)
    // 失敗
    case runFailed(cause: TextID)
    /// 巻き戻した・失って続けたあとの最初のステップで出す(act = .rewound / .continuedWithLoss)。
    case runResumed(act: ActKind, record: ProvenanceID)
    /// 置いた物が壊された(U16。地図に残り、直せる)。
    case placementDestroyed(placement: EntityID, record: ProvenanceID)
    /// 壊れた置いた物を直した(U16)。
    case placementRepaired(placement: EntityID, record: ProvenanceID)
    /// 火床の段が変わった(消えた・点いた・弱まった。U21)。
    case hearthLevelChanged(placement: EntityID, level: HearthLevel)
    /// プレイヤーの操作で火床に燃料をくべた(手触りの振動の合図。A-01)。
    case hearthStoked(placement: EntityID)
    /// 煙・縄張り・闇に引かれて、今夜その獣が寄ることになった(lure のしきい値を越えた。U21)。最初の脅威の引き金。
    case lured(enemy: EnemyKindID)

    /// 物語の出来事の引き金に書く名前。
    public var hook: String {
        switch self {
        case .phaseChanged: "phase"
        case .dawn: "dawn"
        case .factLearned: "fact"
        case .discovered: "discovered"
        case .tilesRevealed: "revealed"
        case .trialed: "trialed"
        case .crafted: "crafted"
        case .designed: "designed"
        case .hintHeard: "hint"
        case .produced: "produced"
        case .moduleStopped: "module.stopped"
        case .moduleResumed: "module.resumed"
        case .placed: "placed"
        case .dismantled: "dismantled"
        case .built: "built"
        case .arrived: "arrived"
        case .walked: "walked"
        case .entered: "entered"
        case .interacted: "interacted"
        case .itemGained: "item.gained"
        case .itemSpent: "item.spent"
        case .finiteUsed: "finite.used"
        case .explored: "explored"
        case .partChanged: "part"
        case .personMet: "person.met"
        case .personJoined: "person.joined"
        case .personLeft: "person.left"
        case .personDied: "person.died"
        case .relationChanged: "relation"
        case .opinion: "opinion"
        case .memoryFormed: "memory"
        case .assigned: "assigned"
        case .statCrossed: "stat"
        case .shortage: "shortage"
        case .bodyChanged: "body"
        case .threatAppeared: "threat"
        case .battleStarted: "battle.started"
        case .battleEnded: "battle.ended"
        case .nestDestroyed: "nest.destroyed"
        case .raided: "raided"
        case .hearthLevelChanged: "hearth"
        case .hearthStoked: "hearth.stoked"
        case .lured: "lured"
        case .trapSprung: "trap.sprung"
        case .researchCompleted: "research.completed"
        case .skillAcquired: "skill"
        case .unlocked: "unlocked"
        case .researchNode: "research.node"
        case .abilityUsed: "ability.used"
        case .eventFired: "event"
        case .decisionOpened: "decision.opened"
        case .decided: "decided"
        case .sceneStarted: "scene"
        case .objectiveChanged: "objective"
        case .chapterEnded: "chapter.ended"
        case .endingReached: "ending"
        case .lineSpoken: "line"
        case .sheetOpened: "sheet.opened"
        case .answerPlaced: "sheet.answered"
        case .grantDeclined: "grant.declined"
        case .rosterDeclared: "roster.declared"
        case .rosterConfirmed: "roster.confirmed"
        case .runFailed: "failed"
        case .runResumed: "run.resumed"
        case .placementDestroyed: "destroyed"
        case .placementRepaired: "repaired"
        }
    }

    /// この出来事に対応する来歴(あれば)。
    public var record: ProvenanceID? {
        switch self {
        case .factLearned(_, let r): r
        case .discovered(_, let r), .trialed(let r), .crafted(_, let r), .designed(_, let r),
             .placed(_, let r), .dismantled(_, let r), .built(_, let r), .interacted(_, _, _, let r),
             .finiteUsed(let r), .personMet(_, let r), .personJoined(_, let r), .personLeft(_, let r),
             .personDied(_, let r), .battleStarted(_, let r), .battleEnded(_, _, _, let r),
             .nestDestroyed(_, let r), .raided(_, let r), .trapSprung(_, let r),
             .researchCompleted(_, let r), .skillAcquired(_, _, let r), .researchNode(_, _, let r),
             .abilityUsed(_, _, let r), .eventFired(_, let r),
             .decided(_, _, let r), .chapterEnded(_, let r), .runResumed(_, let r),
             .explored(_, _, let r), .partChanged(_, _, let r),
             .placementDestroyed(_, let r), .placementRepaired(_, let r):
            r
        case .itemGained(_, _, _, let r): r
        case .hintHeard(_, _, let r): r
        case .opinion(_, let r, _): r
        case .sheetOpened(_, _, _, let r), .answerPlaced(_, _, let r), .grantDeclined(_, _, _, let r),
             .rosterDeclared(_, _, _, let r), .rosterConfirmed(_, let r): r
        default: nil
        }
    }
}
