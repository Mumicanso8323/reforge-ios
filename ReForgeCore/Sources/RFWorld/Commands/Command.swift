import RFKernel
import RFMatter

/// 画面(と出来事の効果)が本体に送る意図。本体はこれを受けて世界を進め、結果と出来事を返す。
/// 画面は世界状態を直接書き換えない(C-engine-ui.md §1)。
///
/// - Codable: コマンドの列と seed があれば走行を再現できる(テスト・不具合の再現)。
/// - 各システムの枝は Commands/<システム>.swift にあり、そのシステムの担当が中身を足す。
/// - 「効果から」と書いた case は出来事の効果が内部で出すもので、画面からは送らない。
public enum Command: Codable, Equatable, Sendable {
    case time(TimeCommand)
    case crew(CrewCommand)
    case invention(InventionCommand)
    case production(ProductionCommand)
    case logistics(LogisticsCommand)
    case exploration(ExplorationCommand)
    case base(BaseCommand)
    case combat(CombatCommand)
    case research(ResearchCommand)
    case abilities(AbilitiesCommand)
    case narrative(NarrativeCommand)
    case survival(SurvivalCommand)
}

public enum TimeCommand: Codable, Equatable, Sendable {
    /// 日没に「夜作業をする」。
    case startNightWork
    /// 寝る(夜明けまで一括で進める)。
    case sleep
}

public enum CrewCommand: Codable, Equatable, Sendable {
    /// ノアを歩かせる(確認なし。歩いている途中に別の行き先を送れば変わる)。
    case walk(to: WorldPoint)
    case stop
    /// 仲間に役割を与える。
    case assign(person: PersonID, assignment: Assignment)
    /// 焚き火のそばで話す(夜作業)。
    case talk(person: PersonID)
    /// 装備を替える。
    case equip(person: PersonID, slot: String, stock: StockSelector)
    // 効果から(持ち主 U5 が処理する。cause = 引き金の来歴。自分の来歴の inputs に入れる)
    /// 人に会う(at があればそこに現れる)。
    case meetFromEffect(person: PersonID, at: WorldPoint?, cause: ProvenanceID?)
    case joinFromEffect(person: PersonID, cause: ProvenanceID?)
    case leaveFromEffect(person: PersonID, cause: ProvenanceID?)
    /// 死ぬ(戻らない)。reason は死因の文字列表のキー。
    case dieFromEffect(person: PersonID, reason: TextID, cause: ProvenanceID?)
    /// 傷を負う(amount は体力の千分率の raw)。
    case injureFromEffect(person: PersonID, amount: Int, cause: ProvenanceID?)
}

public enum InventionCommand: Codable, Equatable, Sendable {
    /// 試作(手持ちの材料を実際に使う)。夜なら時間が進む。
    case trial(input: StockSelector, quantity: Int, steps: [ProcessStep])
    /// 並びをライン札にする。
    case makeDesign(steps: [ProcessStep])
    case discardDesign(design: EntityID)
}

public enum ProductionCommand: Codable, Equatable, Sendable {
    /// ライン札の i 番目の工程のモジュールを置く(置いた瞬間から動く)。
    case placeFromDesign(design: EntityID, stepIndex: Int, at: WorldPoint, facing: Direction)
    /// 単体のモジュールを置く(採掘口など)。
    case place(module: ModuleKindID, at: WorldPoint, facing: Direction)
    case move(placement: EntityID, to: WorldPoint, facing: Direction)
    /// 片付ける(材料は全部戻る。戻せる操作なので確認は出さない)。
    case dismantle(placement: EntityID)
    /// 手作業を押し続ける(押している間 holding = true を送り続ける代わりに、開始と終了の 2 回送る)。
    case handwork(id: HandworkID, input: StockSelector?, holding: Bool)
    /// 有限の品をモジュールに使う(使わなければ取っておいたことになる)。
    case useFinite(placement: EntityID, stock: StockSelector)
    // 効果から(持ち主 U7 が処理する。cause = 引き金の来歴)
    /// 置いてあるモジュールの種類を変える(過去に置いた物も含めて意味が変わる)。
    case convertPlacements(from: ModuleKindID, to: ModuleKindID, cause: ProvenanceID?)
}

public enum LogisticsCommand: Codable, Equatable, Sendable {
    case connect(from: EntityID, to: EntityID)
    case disconnect(route: EntityID)
}

public enum ExplorationCommand: Codable, Equatable, Sendable {
    /// マス・POI・置いた物に対する行為(漁る・汲む・掘る…)。押し続ける行為は holding で始め・終える。
    case interact(interaction: InteractionID, at: WorldPoint, holding: Bool)
    // 効果から(持ち主 U8 が処理する。cause = 引き金の来歴)
    /// 周りの地図を既知にする。
    case revealMap(around: WorldPoint, radius: Int, cause: ProvenanceID?)
    /// 地形を変える。
    case setTerrain(at: WorldPoint, terrain: TerrainID, cause: ProvenanceID?)
    /// 有限の部品の状態を変える(来歴は出来事の側で作って state に入れてある)。
    case setPart(poi: EntityID, part: String, state: PartState)
}

public enum BaseCommand: Codable, Equatable, Sendable {
    case build(structure: StructureKindID, at: WorldPoint, facing: Direction)
    case demolish(placement: EntityID)
    /// 会った生存者を拠点に迎える(拠点の蓄えの食料と、空いている寝床が要る。人数はシェルターの収容で決まる)。
    case welcome(person: PersonID)
}

public enum CombatCommand: Codable, Equatable, Sendable {
    case stance(battle: EntityID, stance: BattleState.Stance)
    case retreat(battle: EntityID)
    /// 効果から: 戦闘を始める。
    case startBattle(enemy: EnemyKindID, count: Int, near: WorldPoint)
    // 効果から(持ち主 U9 が処理する。cause = 引き金の来歴)
    /// 地図の上に敵を出す。
    case spawnEnemy(kind: EnemyKindID, count: Int, near: WorldPoint, cause: ProvenanceID?)
}

public enum ResearchCommand: Codable, Equatable, Sendable {
    case select(research: ResearchID)
    case learnSkill(person: PersonID, skill: SkillID)
}

public enum AbilitiesCommand: Codable, Equatable, Sendable {
    case use(person: PersonID, ability: AbilityID, target: WorldPoint?)
}

public enum NarrativeCommand: Codable, Equatable, Sendable {
    /// 決断を選ぶ。
    case decide(decision: EntityID, choice: ChoiceID)
    /// 場面の次の行へ(読み終えた)。押さなくても時間で流れる。
    case advanceScene
    /// 効果から: 出来事をすぐ起こす(効果 fire)。
    case fireFromEffect(event: EventID, cause: ProvenanceID?)
}

public enum SurvivalCommand: Codable, Equatable, Sendable {
    /// 食べる・飲む(生水か煮沸かは物の種類で選ぶ)。自動の消費とは別に、プレイヤーが選んで口にする。
    case consume(person: PersonID, stock: StockSelector)
    /// 効果から: 体に状態を付ける(中毒・病気…)。重さは状態の定義の単位。
    case afflict(person: PersonID, ailment: StatID, severity: Int)
    /// 効果から: 傷を負う(体力が amount 減り、傷の状態が amount 付く)。効果 injure・戦いの負けが出す。
    case injure(person: PersonID, amount: Int)
}
