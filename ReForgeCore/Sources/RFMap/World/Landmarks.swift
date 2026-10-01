import RFKernel

/// 拠点の整地(原作 `WorldMap.Generate` の中央から横 ±5・縦 ±3 = 11×7)。
public struct BaseArea: Codable, Equatable, Sendable {
    public var center: GridPoint
    public var halfWidth: Int
    public var halfHeight: Int

    public init(center: GridPoint, halfWidth: Int = 5, halfHeight: Int = 3) {
        self.center = center
        self.halfWidth = halfWidth
        self.halfHeight = halfHeight
    }

    public var width: Int { halfWidth * 2 + 1 }
    public var height: Int { halfHeight * 2 + 1 }
    public var minCorner: GridPoint { GridPoint(center.x - halfWidth, center.y - halfHeight) }
    public var maxCorner: GridPoint { GridPoint(center.x + halfWidth, center.y + halfHeight) }

    public func contains(_ p: GridPoint) -> Bool {
        abs(p.x - center.x) <= halfWidth && abs(p.y - center.y) <= halfHeight
    }

    /// 整地の外側までの距離(中なら 0。斜めも 1 と数える)。
    public func ringDistance(_ p: GridPoint) -> Int {
        max(0, max(abs(p.x - center.x) - halfWidth, abs(p.y - center.y) - halfHeight))
    }

    public var cells: [GridPoint] {
        var out: [GridPoint] = []
        for y in minCorner.y...maxCorner.y { for x in minCorner.x...maxCorner.x { out.append(GridPoint(x, y)) } }
        return out
    }
}

/// 地図の目印。拠点・川・岩山・森・遠い残骸の位置関係は seed ごとに変わり、距離の範囲だけが保証される(LandmarkRules)。
public struct Landmarks: Codable, Equatable, Sendable {
    public var base: BaseArea
    /// 川の中心線(上流側から順に、隣り合うマスでつながる。流れか浅瀬のマス)。
    public var river: [GridPoint]
    /// 浅瀬(川を渡れるところ)の中心。
    public var fords: [GridPoint]
    /// 岩山の中心と半径(マス)。
    public var mountainCenter: GridPoint
    public var mountainRadius: Int
    /// 森(拠点と岩山の間に横たわる帯。近道はここを抜ける)。中心は拠点 → 岩山の線と交わるところ。
    public var forestCenter: GridPoint
    /// 森の帯の両端(帯の芯の線分)。
    public var forestEnds: [GridPoint]
    /// 森の帯の半分の厚み(マス)。
    public var forestHalfThickness: Int
    /// 遠くの残骸の位置(川沿いの道の途中、川の内側の岸)。
    public var farWreck: GridPoint
    /// 岩山の手前の露頭(鉄の鉱脈)の位置。
    public var outcrop: GridPoint
    /// 川岸の土石(粘土)の鉱脈の位置。
    public var clayBank: GridPoint

    public init(base: BaseArea, river: [GridPoint], fords: [GridPoint], mountainCenter: GridPoint, mountainRadius: Int,
                forestCenter: GridPoint, forestEnds: [GridPoint], forestHalfThickness: Int,
                farWreck: GridPoint, outcrop: GridPoint, clayBank: GridPoint) {
        self.base = base
        self.river = river
        self.fords = fords
        self.mountainCenter = mountainCenter
        self.mountainRadius = mountainRadius
        self.forestCenter = forestCenter
        self.forestEnds = forestEnds
        self.forestHalfThickness = forestHalfThickness
        self.farWreck = farWreck
        self.outcrop = outcrop
        self.clayBank = clayBank
    }
}

/// 目印の位置関係の保証(距離はマスのユークリッド距離。拠点の中心から測る)。
/// 経路の保証は Pathfinder で霧を見ずに測る(既定の移動コスト)。
/// R1 の 96×96 を基準にした値。地図が小さいときは `scaled(to:)` で縮める。
public struct LandmarkRules: Codable, Equatable, Sendable {
    /// いちばん近い水(水辺・川)のマス(拠点から最初の視界の中に見える)。
    public var nearestWater: ClosedRange<Double>
    /// 拠点のまわりの空き(この幅の輪に水・岩場・遺跡を置かない)。
    public var baseClearance: Int
    /// 岩山の中心。
    public var mountain: ClosedRange<Double>
    /// 露頭(岩山の手前の鉄の鉱脈)。
    public var outcrop: ClosedRange<Double>
    /// 森の中心。
    public var forest: ClosedRange<Double>
    /// 拠点 → 露頭の最安経路が森を踏むマス数の下限(森が近道)。
    public var forestOnShortcut: Int
    /// 森を避けた経路のコスト ÷ 最安経路のコスト の下限(森を避ける安全な道は遠い)。
    public var safeRouteCostRatio: Double
    /// 遠い残骸。
    public var farWreck: ClosedRange<Double>
    /// 遠い残骸から川の中心線までの距離の上限。
    public var farWreckToRiver: Double
    /// 遠い残骸が近道(拠点 → 露頭の最安経路)から離れている距離の下限。
    public var farWreckOffShortcut: Double
    /// 拠点 → 遠い残骸の最安経路のうち、川の中心線から `wreckRouteRiverBand` 以内を歩く割合の下限(川沿いを通る)。
    public var wreckRouteNearRiver: Double
    public var wreckRouteRiverBand: Double
    /// 川が岩山の中心に近づく距離(岩山へ川沿いで行ける)。岩山の中には入らない。
    public var riverToMountain: ClosedRange<Double>
    /// 浅瀬の間隔(川の中心線のマス数)。
    public var fordSpacing: Int
    /// 目印と地図の端の間の空き。
    public var edgeMargin: Int
    /// 拠点のまわりの草地の半径。この内側の下地は岩場と遺跡を出さず、森と水辺も控えめにする
    /// (外側 6 マスで通常の判定へなめらかに戻す)。これで岩山がいちばん近い岩場になる。
    public var homeZoneRadius: Double

    public init(nearestWater: ClosedRange<Double>, baseClearance: Int, mountain: ClosedRange<Double>,
                outcrop: ClosedRange<Double>, forest: ClosedRange<Double>, forestOnShortcut: Int,
                safeRouteCostRatio: Double, farWreck: ClosedRange<Double>, farWreckToRiver: Double,
                farWreckOffShortcut: Double, wreckRouteNearRiver: Double, wreckRouteRiverBand: Double,
                riverToMountain: ClosedRange<Double>, fordSpacing: Int, edgeMargin: Int, homeZoneRadius: Double) {
        self.nearestWater = nearestWater
        self.baseClearance = baseClearance
        self.mountain = mountain
        self.outcrop = outcrop
        self.forest = forest
        self.forestOnShortcut = forestOnShortcut
        self.safeRouteCostRatio = safeRouteCostRatio
        self.farWreck = farWreck
        self.farWreckToRiver = farWreckToRiver
        self.farWreckOffShortcut = farWreckOffShortcut
        self.wreckRouteNearRiver = wreckRouteNearRiver
        self.wreckRouteRiverBand = wreckRouteRiverBand
        self.riverToMountain = riverToMountain
        self.fordSpacing = fordSpacing
        self.edgeMargin = edgeMargin
        self.homeZoneRadius = homeZoneRadius
    }

    private enum CodingKeys: String, CodingKey {
        case nearestWater, baseClearance, mountain, outcrop, forest, forestOnShortcut, safeRouteCostRatio, farWreck,
             farWreckToRiver, farWreckOffShortcut, wreckRouteNearRiver, wreckRouteRiverBand, riverToMountain,
             fordSpacing, edgeMargin, homeZoneRadius
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(nearestWater: try c.decodeMicroRange(.nearestWater), baseClearance: try c.decode(Int.self, forKey: .baseClearance),
                  mountain: try c.decodeMicroRange(.mountain), outcrop: try c.decodeMicroRange(.outcrop),
                  forest: try c.decodeMicroRange(.forest), forestOnShortcut: try c.decode(Int.self, forKey: .forestOnShortcut),
                  safeRouteCostRatio: try c.decodeMicro(.safeRouteCostRatio), farWreck: try c.decodeMicroRange(.farWreck),
                  farWreckToRiver: try c.decodeMicro(.farWreckToRiver), farWreckOffShortcut: try c.decodeMicro(.farWreckOffShortcut),
                  wreckRouteNearRiver: try c.decodeMicro(.wreckRouteNearRiver), wreckRouteRiverBand: try c.decodeMicro(.wreckRouteRiverBand),
                  riverToMountain: try c.decodeMicroRange(.riverToMountain), fordSpacing: try c.decode(Int.self, forKey: .fordSpacing),
                  edgeMargin: try c.decode(Int.self, forKey: .edgeMargin), homeZoneRadius: try c.decodeMicro(.homeZoneRadius))
    }

    /// 実数は 100 万分の 1 単位の整数で書く(保存に小数を入れない)。
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeMicro(nearestWater, forKey: .nearestWater)
        try c.encode(baseClearance, forKey: .baseClearance)
        try c.encodeMicro(mountain, forKey: .mountain)
        try c.encodeMicro(outcrop, forKey: .outcrop)
        try c.encodeMicro(forest, forKey: .forest)
        try c.encode(forestOnShortcut, forKey: .forestOnShortcut)
        try c.encodeMicro(safeRouteCostRatio, forKey: .safeRouteCostRatio)
        try c.encodeMicro(farWreck, forKey: .farWreck)
        try c.encodeMicro(farWreckToRiver, forKey: .farWreckToRiver)
        try c.encodeMicro(farWreckOffShortcut, forKey: .farWreckOffShortcut)
        try c.encodeMicro(wreckRouteNearRiver, forKey: .wreckRouteNearRiver)
        try c.encodeMicro(wreckRouteRiverBand, forKey: .wreckRouteRiverBand)
        try c.encodeMicro(riverToMountain, forKey: .riverToMountain)
        try c.encode(fordSpacing, forKey: .fordSpacing)
        try c.encode(edgeMargin, forKey: .edgeMargin)
        try c.encodeMicro(homeZoneRadius, forKey: .homeZoneRadius)
    }

    /// R1(96×96)の保証。
    public static let r1 = LandmarkRules(
        nearestWater: 4...8, baseClearance: 1,
        mountain: 25...32, outcrop: 17...30,
        forest: 11...20, forestOnShortcut: 4, safeRouteCostRatio: 1.2,
        farWreck: 20...40, farWreckToRiver: 6, farWreckOffShortcut: 8,
        wreckRouteNearRiver: 0.5, wreckRouteRiverBand: 6,
        riverToMountain: 5...12, fordSpacing: 22,
        edgeMargin: 3, homeZoneRadius: 30
    )

    /// 短い辺が 96 より小さい地図に合わせて距離を縮める(大きい地図はそのまま)。
    public func scaled(to size: MapSize) -> LandmarkRules {
        let k = min(1, Double(min(size.width, size.height)) / 96)
        guard k < 1 else { return self }
        // 縮めた値は保存の単位(100 万分の 1)に丸める(保存して読み直しても同じ設定になる)
        let q = Micro.quantize
        func s(_ r: ClosedRange<Double>) -> ClosedRange<Double> { q(r.lowerBound * k)...q(r.upperBound * k) }
        var r = self
        // 拠点の大きさは縮めないので水辺はそのまま
        r.mountain = s(mountain)
        r.outcrop = s(outcrop)
        r.forest = s(forest)
        r.farWreck = s(farWreck)
        r.farWreckToRiver = q(max(3, farWreckToRiver * k))
        r.farWreckOffShortcut = q(farWreckOffShortcut * k)
        r.wreckRouteRiverBand = q(max(3, wreckRouteRiverBand * k))
        r.riverToMountain = s(riverToMountain)
        r.homeZoneRadius = q(homeZoneRadius * k)
        r.forestOnShortcut = max(1, Int((Double(forestOnShortcut) * k).rounded(.down)))
        r.fordSpacing = max(8, Int((Double(fordSpacing) * k).rounded()))
        return r
    }
}
