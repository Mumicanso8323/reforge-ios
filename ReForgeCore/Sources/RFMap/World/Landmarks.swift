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
    /// 川の中心線(上流側から順に、隣り合うマスでつながる)。
    public var river: [GridPoint]
    /// 岩山の中心と半径(マス)。
    public var mountainCenter: GridPoint
    public var mountainRadius: Int
    /// 森(拠点と岩山の間の近道)の中心と半径。
    public var forestCenter: GridPoint
    public var forestRadius: Int
    /// 先に来た誰かの残骸の位置(川沿いの遠回りの先)。
    public var farWreck: GridPoint
    /// 岩山の手前の露頭(鉄の鉱脈)の位置。
    public var outcrop: GridPoint
    /// 川岸の土石(粘土)の鉱脈の位置。
    public var clayBank: GridPoint

    public init(base: BaseArea, river: [GridPoint], mountainCenter: GridPoint, mountainRadius: Int,
                forestCenter: GridPoint, forestRadius: Int, farWreck: GridPoint, outcrop: GridPoint, clayBank: GridPoint) {
        self.base = base
        self.river = river
        self.mountainCenter = mountainCenter
        self.mountainRadius = mountainRadius
        self.forestCenter = forestCenter
        self.forestRadius = forestRadius
        self.farWreck = farWreck
        self.outcrop = outcrop
        self.clayBank = clayBank
    }
}

/// 目印の位置関係の保証(距離はマスのユークリッド距離。拠点の中心から測る)。
/// R1 の 96×96 を基準にした値。地図が小さいときは `scaled(to:)` で縮める。
public struct LandmarkRules: Codable, Equatable, Sendable {
    /// いちばん近い水辺のマス(拠点から最初の視界の中に見える)。
    public var nearestWater: ClosedRange<Double>
    /// 拠点のまわりの空き(この幅の輪に水辺・岩場・遺跡を置かない)。
    public var baseClearance: Int
    /// 岩山の中心。
    public var mountain: ClosedRange<Double>
    /// 露頭(岩山の手前の鉄の鉱脈)。
    public var outcrop: ClosedRange<Double>
    /// 森の中心。
    public var forest: ClosedRange<Double>
    /// 拠点 → 岩山の直線が森を通るマス数の下限(森が近道になる)。
    public var forestOnShortcut: Int
    /// 遠い残骸。
    public var farWreck: ClosedRange<Double>
    /// 遠い残骸から川までの距離の上限(川沿いの道の先にある)。
    public var farWreckToRiver: Double
    /// 遠い残骸が拠点 → 岩山の直線から離れている距離の下限(近道の上には無い)。
    public var farWreckOffShortcut: Double
    /// 川が岩山の中心に近づく距離(岩山へ川沿いで行ける)。岩山の中には入らない。
    public var riverToMountain: ClosedRange<Double>
    /// 川沿いの道の長さ ÷ 直線の長さ の下限(川沿いは遠回り)。
    public var riverDetourRatio: Double
    /// 目印と地図の端の間の空き。
    public var edgeMargin: Int
    /// 拠点のまわりの草地の半径。この内側の下地は岩場と遺跡を出さず、森と水辺も控えめにする
    /// (外側 6 マスで通常の判定へなめらかに戻す)。これで岩山がいちばん近い岩場になる。
    public var homeZoneRadius: Double

    public init(nearestWater: ClosedRange<Double>, baseClearance: Int, mountain: ClosedRange<Double>,
                outcrop: ClosedRange<Double>, forest: ClosedRange<Double>, forestOnShortcut: Int,
                farWreck: ClosedRange<Double>, farWreckToRiver: Double, farWreckOffShortcut: Double,
                riverToMountain: ClosedRange<Double>, riverDetourRatio: Double, edgeMargin: Int,
                homeZoneRadius: Double) {
        self.nearestWater = nearestWater
        self.baseClearance = baseClearance
        self.mountain = mountain
        self.outcrop = outcrop
        self.forest = forest
        self.forestOnShortcut = forestOnShortcut
        self.farWreck = farWreck
        self.farWreckToRiver = farWreckToRiver
        self.farWreckOffShortcut = farWreckOffShortcut
        self.riverToMountain = riverToMountain
        self.riverDetourRatio = riverDetourRatio
        self.edgeMargin = edgeMargin
        self.homeZoneRadius = homeZoneRadius
    }

    /// R1(96×96)の保証。
    public static let r1 = LandmarkRules(
        nearestWater: 4...8, baseClearance: 1,
        mountain: 24...32, outcrop: 18...30,
        forest: 9...19, forestOnShortcut: 4,
        farWreck: 24...40, farWreckToRiver: 8, farWreckOffShortcut: 10,
        riverToMountain: 5...12, riverDetourRatio: 1.3,
        edgeMargin: 3, homeZoneRadius: 30
    )

    /// 短い辺が 96 より小さい地図に合わせて距離を縮める(大きい地図はそのまま)。
    public func scaled(to size: MapSize) -> LandmarkRules {
        let k = min(1, Double(min(size.width, size.height)) / 96)
        guard k < 1 else { return self }
        func s(_ r: ClosedRange<Double>) -> ClosedRange<Double> { (r.lowerBound * k)...(r.upperBound * k) }
        var r = self
        r.nearestWater = nearestWater.lowerBound...nearestWater.upperBound   // 拠点の大きさは縮めないので水辺もそのまま
        r.mountain = s(mountain)
        r.outcrop = s(outcrop)
        r.forest = s(forest)
        r.farWreck = s(farWreck)
        r.farWreckToRiver = farWreckToRiver * k
        r.farWreckOffShortcut = farWreckOffShortcut * k
        r.riverToMountain = s(riverToMountain)
        r.homeZoneRadius = homeZoneRadius * k
        r.forestOnShortcut = max(1, Int((Double(forestOnShortcut) * k).rounded(.down)))
        return r
    }
}
