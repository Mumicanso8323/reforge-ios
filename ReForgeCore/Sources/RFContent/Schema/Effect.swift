import RFKernel
import RFMatter

/// 出来事・選択肢・研究の完了などが世界に与える変化。宣言的なデータで、適用は RFRules.EffectApplier。
/// 「文を出すだけ」の出来事を基本にしない: 効果は世界の状態を変える(場面 startScene は添え物)。
///
/// 効果が起こした変化は来歴に残り、inputs に引き金の来歴が入る(後で「何がきっかけだったか」を辿れる)。
public enum Effect: Codable, Hashable, Sendable {
    // 知る
    case learn(fact: FactID)
    // 物
    /// 物を渡す(item か matter のどちらか)。unique = 唯一品として(来歴で後から指せる)。
    case give(item: ItemID?, matter: Matter?, quantity: Int, unique: Bool?)
    case take(what: Ingredient)
    // 数
    case counter(id: CounterID, add: Int)
    case setCounter(id: CounterID, value: Int)
    case stat(id: StatID, add: Int)
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
    /// 仲間の配属を上書きする(プレイヤーの配属に従わない)。toward があればその場所へ歩く。
    case overrideAssignment(person: PersonID, toward: PlaceSelector?, hours: Int?)
    case clearOverride(person: PersonID)
    // 範囲の効果
    /// 範囲の効果を付ける(人・地点・置いた物を中心に)。
    case addAura(kind: AuraKindID, at: PlaceSelector, radius: Int, hours: Int?)
    /// 強さを千分率で掛ける(500 = 半分)。0 で消える。
    case scaleAura(kind: AuraKindID, permille: Int)
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
    case schedule(event: EventID, afterMinutes: Int)
    case objective(id: ObjectiveID, status: ObjectiveStatusName)
    case chapter(id: ChapterID)
    case ending(id: EndingID)
}

/// 部品の状態の名前(RFWorld の PartState と対応)。
public enum PartStateName: String, Codable, Hashable, Sendable { case intact, salvaged, dismantled, rebuilt }
