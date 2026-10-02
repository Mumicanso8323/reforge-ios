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
    /// 効果から(U16): 近くのモジュールを壊す(近い順、max 個まで)。
    case destroyFromEffect(near: WorldPoint, radius: Int, module: ModuleKindID?, max: Int?, cause: ProvenanceID?)
    /// 壊れたモジュールを直す(置くときと同じ材料を払う。U16)。
    case repair(placement: EntityID)
}

public enum LogisticsCommand: Codable, Equatable, Sendable {
    /// 端と端を運搬の経路で結ぶ(拠点の蓄えも端にできる)。同じ端の組がもうあれば何もしない。
    case link(from: HaulEndpoint, to: HaulEndpoint)
    /// モジュールとモジュールを運搬の経路で結ぶ(link の短い書き方)。
    case connect(from: EntityID, to: EntityID)
    case disconnect(route: EntityID)
}

public enum ExplorationCommand: Codable, Equatable, Sendable {
    /// マス・POI・置いた物に対する行為(漁る・汲む・掘る…)。押し続ける行為は holding で始め・終える。
    /// person = 誰がするか(nil はノア)。その人が対象のそばにいなければ断る。
    case interact(interaction: InteractionID, at: WorldPoint, holding: Bool, person: PersonID? = nil)
    // 効果から(持ち主 U8 が処理する。cause = 引き金の来歴)
    /// 周りの地図を既知にする。
    case revealMap(around: WorldPoint, radius: Int, cause: ProvenanceID?)
    /// 地形を変える。
    case setTerrain(at: WorldPoint, terrain: TerrainID, cause: ProvenanceID?)
    /// 有限の部品の状態を変える(来歴は出来事の側で作って state に入れてある)。
    case setPart(poi: EntityID, part: String, state: PartState)
    /// 地図の光の点を置く・消す(at nil で消す。U19)。
    case setBeacon(id: String, at: WorldPoint?, cause: ProvenanceID?)
    /// 長押しで調べたマスの種類を覚える(U20。GameHost.inspect が送る。時計の保留は解かない)。
    case inspected(terrain: TerrainID?, poi: POIKindID?)
}

public enum BaseCommand: Codable, Equatable, Sendable {
    case build(structure: StructureKindID, at: WorldPoint, facing: Direction)
    case demolish(placement: EntityID)
    /// 会った生存者を拠点に迎える(拠点の蓄えの食料と、空いている寝床が要る。人数はシェルターの収容で決まる)。
    case welcome(person: PersonID)
    /// 効果から(U16): 近くの建造物を壊す(近い順、max 個まで)。
    case destroyFromEffect(near: WorldPoint, radius: Int, structure: StructureKindID?, max: Int?, cause: ProvenanceID?)
    /// 壊れた建造物を直す(建てるときと同じ材料を払う。U16)。
    case repair(placement: EntityID)
    /// 火床をくべる・積む・点け直す・埋める(U21)。
    case hearth(placement: EntityID, op: HearthOp)
}

public enum CombatCommand: Codable, Equatable, Sendable {
    case stance(battle: EntityID, stance: BattleState.Stance)
    case retreat(battle: EntityID)
    /// 戦闘が始まったときの方針(寝ている間の戦闘もこれで進む)。
    case setDefaultStance(stance: BattleState.Stance)
    /// 効果から: 戦闘を始める。
    case startBattle(enemy: EnemyKindID, count: Int, near: WorldPoint)
    // 効果から(持ち主 U9 が処理する。cause = 引き金の来歴)
    /// 地図の上に敵を出す。
    case spawnEnemy(kind: EnemyKindID, count: Int, near: WorldPoint, cause: ProvenanceID?)
    /// 効果から(U16): 拠点の外の集団と戦う(groupBattle)。
    case startGroupBattle(group: GroupID, near: WorldPoint, members: [PersonID]?, lethal: Bool, cause: ProvenanceID?)
}

public enum ResearchCommand: Codable, Equatable, Sendable {
    /// 進める研究パッケージを選ぶ(研究机に付いた人が昼に進める)。別のを選べば切り替わる(進みは残る)。
    case select(research: ResearchID)
    /// スキルを習い始める(習得の時間のあいだは「学ぶ時期」。BEAT-15)。
    case learnSkill(person: PersonID, skill: SkillID)
    /// 習うのをやめる(進みは残る。同じスキルを選び直せば続きから)。
    case stopLearning(person: PersonID)
    /// 夜作業: 研究机で研究する(ResearchRules.nightStudyHours だけ時間が進む)。
    case nightStudy(person: PersonID)
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
    // 工程表(U15)
    /// 工程表を開く(slot nil = 表 / 番号 = 記録の 1 件。空いた席も開ける)。開いたことは来歴に残る。
    case openSheet(sheet: SheetID, slot: Int?)
    /// 装置で技能を書き足す(skill nil = この人には使わないと決める)。
    case imprint(sheet: SheetID, person: PersonID, skill: SkillID?)
    /// 行に自分の来歴を答えとして置く(置き直せる)。
    case placeAnswer(sheet: SheetID, row: String, record: ProvenanceID)
    /// 名簿で「乗る / 残る」を決める(ノアも)。
    case setBoarding(sheet: SheetID, person: PersonID, aboard: Bool)
    /// 名簿を締める(出発)。
    case lockManifest(sheet: SheetID)
}

public enum SurvivalCommand: Codable, Equatable, Sendable {
    /// 食べる・飲む(生水か煮沸かは物の種類で選ぶ)。自動の消費とは別に、プレイヤーが選んで口にする。
    case consume(person: PersonID, stock: StockSelector)
    /// 効果から: 体に状態を付ける(中毒・病気…)。重さは状態の定義の単位。
    /// cause: 引き金の来歴(戦いの終わり・出来事の効果など)。wasInjured の来歴の inputs に入る(REQ-S6)。
    case afflict(person: PersonID, ailment: StatID, severity: Int, cause: ProvenanceID? = nil)
    /// 効果から: 傷を負う(体力が amount 減り、傷の状態が amount 付く。amount は体の値の整数の点)。効果 injure・戦いの負けが出す。
    /// cause: 引き金の来歴。wasInjured の来歴の inputs に入り、死んだときに RFCrew がそこから辿る。
    case injure(person: PersonID, amount: Int, cause: ProvenanceID? = nil)
}
