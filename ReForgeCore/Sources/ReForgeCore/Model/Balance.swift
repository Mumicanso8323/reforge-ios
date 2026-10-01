/// MVP の数値(§6)。仮値はここを差し替えるだけで変わる。
public struct Balance: Equatable, Sendable {
    /// 主人公(OPEN-04 確定: 名前は「ノア」で固定)。
    public var protagonistName = "ノア"
    /// 初期の仲間(§6.1。GameState.cs:521-536)。人口 = 1 + 仲間の数。
    public var initialCompanions = ["クロム", "シリカ", "カーボ", "ルーメン"]
    /// 初期在庫(§6.1。食料 15+10、銅鉱石は持たせない)。
    public var initialInventory: [ItemID: Int] = [
        ID.food: 25, ID.water: 18, ID.wood: 20, ID.stone: 5, ID.ironOre: 5,
    ]
    public var scavengeCount = 10
    /// 食料・水の保管上限(Normal 60、保管箱で 120)。
    public var foodWaterCap = 60
    public var foodWaterCapWithCrate = 120

    /// 1 人 1 日あたりの消費(§6.2)。
    public var foodPerPersonPerDay = 1
    public var waterPerPersonPerDay = 1
    /// 食料切れ・水切れが何日続くと倒れるか(§6.2)。
    public var starvationDays = 5
    public var dehydrationDays = 3
    /// 警告帯: 何日分を切ったら黄色にするか(§7 S1)。
    public var lowStockWarningDays = 2

    // 採取(§6.3)
    public var gatherFood = 4
    public var gatherFoodCampfireBonus = 1
    public var gatherWater = 4
    public var chopWood = 5
    public var chopFiberChancePercent = 20
    public var quarryStone = 3
    public var quarryClayChancePercent = 30
    public var mineOre = 3
    public var mineCoal = 2
    /// 残骸漁りの保存食: min + 0..<spread(Core: 2 + rng.Next(3))。
    public var scavengeRationMin = 2
    public var scavengeRationSpread = 3

    // 建造物の 1 日あたりの効果(§6.5)
    public var wellWaterPerDay = 2
    public var farmCyclesPerDay = 1
    public var farmWaterIn = 1
    public var farmFoodOut = 2
    public var charcoalPitCyclesPerDay = 1
    public var charcoalPitWoodIn = 3
    public var charcoalPitCharcoalOut = 2

    // 勝利(§4.3)
    public var victoryDay = 30
    public var victoryBuildings: [BuildingID] = [ID.well, ID.simpleFarm, ID.basicFurnace]

    /// 日誌の保持件数(§5.5)。
    public var logLimit = 200

    public init() {}

    public static let mvp = Balance()
}
