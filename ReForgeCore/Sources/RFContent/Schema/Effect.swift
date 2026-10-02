import RFKernel
import RFMatter

/// 出来事・選択肢・研究の完了・目標の達成などが世界に与える変化。宣言的なデータで、適用は RFRules.EffectApplier。
/// 「文を出すだけ」の出来事を基本にしない: 効果の本体は世界の状態を変えること(場面 startScene・一言 say は添え物)。
///
/// 効果が起こした変化は来歴に残り、inputs に引き金の来歴が入る(後で「何がきっかけだったか」を辿れる)。
/// 他のシステムの切れ端を変える効果(人の合流・地形・部品・敵・置いた物の変換)は、そのシステムへのコマンドになる。
/// 省略可能(`?`)なラベルは JSON で書かなくてよい。
public enum Effect: Codable, Hashable, Sendable {
    // 知る
    case learn(fact: FactID)
    // 物
    /// 物を渡す(item か matter のどちらか)。unique = 唯一品として(来歴で後から指せる)。
    /// attributes = 品そのものに持たせる属性(例 "owner": 遺品の持ち主)。
    case give(item: ItemID?, matter: Matter?, quantity: Int, unique: Bool?, attributes: [String: String]? = nil)
    case take(what: Ingredient)
    // 数
    case counter(id: CounterID, add: Int)
    case setCounter(id: CounterID, value: Int)
    /// 拠点全体の数値を足す(千分率の raw)。
    case stat(id: StatID, add: Int)
    case setStat(id: StatID, value: Int)
    // 人
    case relation(person: PersonID, add: Int)
    case ideology(person: PersonID, axis: IdeologyAxisID, add: Int)
    /// 仲間が記憶する(about は引き金の来歴)。persists = 巻き戻しをまたいで残る。
    case remember(person: PersonID, memory: MemoryKindID, persists: Bool)
    case meet(person: PersonID, at: PlaceSelector)
    case join(person: PersonID)
    case leave(person: PersonID)
    case die(person: PersonID, cause: TextID)
    case injure(person: PersonID, amount: Int)
    /// 仲間の配属を上書きする(プレイヤーの配属に従わない)。toward があればその場所へ歩く。hours の後に戻る。
    case overrideAssignment(person: PersonID, toward: PlaceSelector?, hours: Int?)
    case clearOverride(person: PersonID)
    /// 仲間の一言(文脈に合う LineDef を条件と重みで選ぶ。speaker を指定しなければ誰でも)。
    case say(context: String, speaker: PersonID?)
    // 拠点の外の集団
    case groupRelation(id: GroupID, add: Int)
    case groupFlag(id: GroupID, flag: String, on: Bool)
    // 範囲の効果
    /// 範囲の効果を付ける(人・地点・置いた物を中心に)。radius が無ければ AuraDef.radius。strength は千分率(既定 1000)。
    case addAura(kind: AuraKindID, at: PlaceSelector, radius: Int?, hours: Int?, strength: Int? = nil)
    /// 強さを千分率で掛ける(500 = 半分。0 で消える)。radiusPermille があれば半径も掛ける(範囲が目に見えて縮む)。
    /// この種類の今ある範囲と、これから付く範囲(置いた物・人の定義から付くもの)の両方に効く。
    case scaleAura(kind: AuraKindID, permille: Int, radiusPermille: Int? = nil)
    case removeAura(kind: AuraKindID)
    // 有限の部品
    case setPart(poiKind: POIKindID, part: String, state: PartStateName)
    // 地図
    case revealMap(around: PlaceSelector, radius: Int)
    case setTerrain(at: PlaceSelector, terrain: TerrainID)
    case spawnEnemy(kind: EnemyKindID, count: Int, near: PlaceSelector)
    case startBattle(enemy: EnemyKindID, count: Int, near: PlaceSelector)
    // 置いた物の意味が変わる(過去に置いた物も含めて)
    case convertPlacements(from: ModuleKindID, to: ModuleKindID)
    /// 条件に合う過去の来歴に印を付ける(後の開示・条件がその印で指せる)。
    case tagRecords(query: ProvenanceQuery, tag: ProvenanceTag)
    // 解禁
    case unlock(target: UnlockTarget)
    // 物語
    case startScene(scene: SceneID)
    /// 出来事を予約する(afterMinutes ゲーム分の後。起きるときに trigger.when をもう一度確かめる)。
    case schedule(event: EventID, afterMinutes: Int)
    /// 予約を取り消す。
    case unschedule(event: EventID)
    /// 出来事をすぐ起こす(trigger.when は見ない。一度きりの出来事が起きた後なら何もしない)。選択肢から別の筋へ進むときに使う。
    case fire(event: EventID)
    case objective(id: ObjectiveID, status: ObjectiveStatusName)
    case chapter(id: ChapterID)
    case ending(id: EndingID)
    // U16: 置いた物を壊す・人の集団どうしの戦い
    /// 場所の近く(チェビシェフ距離 radius 以内)の置いた物を壊す(近い順、max 個まで。既定は全部)。
    /// module・structure で種類を絞る(両方 nil なら全部の種類。片方だけならその側だけ)。
    /// 壊れた物は地図に残って止まり(status broken)、入口と出口の待ちは失われる。来歴 destroyed に残り、直せる。
    case destroyPlacements(near: PlaceSelector, radius: Int, module: ModuleKindID? = nil,
                           structure: StructureKindID? = nil, max: Int? = nil)
    /// 拠点の外の集団と戦う(1 次元の帯の自動戦闘。D11)。味方は at の近くにいる一員、相手はその集団の生きている人
    /// (members で名指しできる)。lethal = 倒れた人が死ぬか(既定 true。死者は戻らない)。
    /// 終わると集団の旗 "battle.won" / "battle.lost" / "battle.fled" が立つ(条件 groupFlag で見る)。
    case groupBattle(group: GroupID, at: PlaceSelector, members: [PersonID]? = nil, lethal: Bool? = nil)
    // U19: 地図の光の点(遠くの灯りなど。暗闇でも描く)
    /// 地図に光の点を置く(同じ id なら置き直す)。id は中立の名前にする。
    case beacon(id: String, at: PlaceSelector)
    /// 光の点を消す(無ければ何もしない)。
    case clearBeacon(id: String)
}

/// 部品の状態の名前(RFWorld の PartState と対応)。
public enum PartStateName: String, Codable, Hashable, Sendable { case intact, salvaged, dismantled, rebuilt }
