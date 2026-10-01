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
    case produced(placement: EntityID, quantity: Int)
    case moduleStopped(placement: EntityID, reason: TextID)
    case moduleResumed(placement: EntityID)
    // 置く・建てる
    case placed(placement: EntityID, record: ProvenanceID)
    case dismantled(placement: EntityID, record: ProvenanceID)
    case built(placement: EntityID, record: ProvenanceID)
    // 動く・探す
    case arrived(person: PersonID, at: WorldPoint)
    case entered(person: PersonID, poi: EntityID)
    case interacted(person: PersonID, interaction: InteractionID, at: WorldPoint, record: ProvenanceID)
    case itemGained(holder: HolderID, stuff: Stuff, quantity: Int, record: ProvenanceID?)
    case itemSpent(holder: HolderID, stuff: Stuff, quantity: Int)
    case finiteUsed(record: ProvenanceID)
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
    // 研究
    case researchCompleted(research: ResearchID, record: ProvenanceID)
    case skillAcquired(person: PersonID, skill: SkillID, record: ProvenanceID)
    case unlocked(what: String)
    // 物語
    case eventFired(event: EventID, record: ProvenanceID)
    case decisionOpened(decision: EntityID, event: EventID)
    case decided(decision: EntityID, choice: ChoiceID, record: ProvenanceID)
    case sceneStarted(scene: SceneID)
    case objectiveChanged(objective: ObjectiveID, status: ObjectiveStatus)
    case chapterEnded(chapter: ChapterID, record: ProvenanceID)
    case endingReached(ending: EndingID)
    // 失敗
    case runFailed(cause: TextID)
    /// 巻き戻した・失って続けたあとの最初のステップで出す(act = .rewound / .continuedWithLoss)。
    case runResumed(act: ActKind, record: ProvenanceID)

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
        case .produced: "produced"
        case .moduleStopped: "module.stopped"
        case .moduleResumed: "module.resumed"
        case .placed: "placed"
        case .dismantled: "dismantled"
        case .built: "built"
        case .arrived: "arrived"
        case .entered: "entered"
        case .interacted: "interacted"
        case .itemGained: "item.gained"
        case .itemSpent: "item.spent"
        case .finiteUsed: "finite.used"
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
        case .researchCompleted: "research.completed"
        case .skillAcquired: "skill"
        case .unlocked: "unlocked"
        case .eventFired: "event"
        case .decisionOpened: "decision.opened"
        case .decided: "decided"
        case .sceneStarted: "scene"
        case .objectiveChanged: "objective"
        case .chapterEnded: "chapter.ended"
        case .endingReached: "ending"
        case .runFailed: "failed"
        case .runResumed: "run.resumed"
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
             .researchCompleted(_, let r), .skillAcquired(_, _, let r), .eventFired(_, let r),
             .decided(_, _, let r), .chapterEnded(_, let r), .runResumed(_, let r):
            r
        case .itemGained(_, _, _, let r): r
        case .opinion(_, let r, _): r
        default: nil
        }
    }
}
