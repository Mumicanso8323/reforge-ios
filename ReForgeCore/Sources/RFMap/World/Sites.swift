import RFKernel

/// コンテンツが決める場所(砦・別の集団の拠点など。U16)の置き方の規則。
/// 拠点の中心からの距離(マス。96×96 の地図を基準にし、小さい地図では目印と同じく縮める)の範囲に、
/// 通れる乾いた土地で、拠点から歩いて行ける所を選んで POI として置く。
public struct SiteRule: Codable, Equatable, Sendable {
    /// 配置物の ID(層の中で一意。例 "site.test.fort")。
    public var id: String
    /// POI の種類(POIState.kind・PlaceSelector.poiKind・PersonDef.home で指す)。
    public var poi: POIKindID
    /// 配置物の種類(既定 settlement)。
    public var kind: String?
    public var minDistance: Int
    public var maxDistance: Int
    /// 占めるマス(既定 2×2)。
    public var width: Int?
    public var height: Int?

    public init(id: String, poi: POIKindID, kind: String? = nil, minDistance: Int, maxDistance: Int,
                width: Int? = nil, height: Int? = nil) {
        self.id = id
        self.poi = poi
        self.kind = kind
        self.minDistance = minDistance
        self.maxDistance = maxDistance
        self.width = width
        self.height = height
    }
}

/// 場所を置く(WorldMap.generate が固定の配置物の後に呼ぶ)。
/// 乱数は場所ごとに seed から別に引く(SeededRandom.derived(seed, 300, i))。sites が無ければ何も引かない。
public enum Sites {
    /// 1 つの場所に試す候補の数。
    static let attempts = 600

    static func place(_ rules: [SiteRule], in layer: inout MapLayer, landmarks lm: Landmarks, seed: UInt64) {
        let size = layer.terrain.size
        let k = min(1.0, Double(min(size.width, size.height)) / 96)
        let o = lm.base.center
        for (i, r) in rules.enumerated() {
            var rng = SeededRandom.derived(from: seed, 300, i)
            let lo = max(0, Int((Double(r.minDistance) * k).rounded()))
            let hi = max(lo + 1, Int((Double(r.maxDistance) * k).rounded()))
            let fp = TileFootprint.rect(width: max(1, r.width ?? 2), height: max(1, r.height ?? 2))
            var placed = false
            // 1 回目は範囲どおり、見つからなければ範囲を少しずつ広げる(どの seed でも置く)
            for widen in 0..<4 where !placed {
                let a = max(0, lo - widen * 3), b = hi + widen * 3
                for _ in 0..<attempts {
                    let p = GridPoint(o.x + rng.int(in: -b...b), o.y + rng.int(in: -b...b))
                    let d = p.distance(to: o)
                    guard d >= Double(a), d <= Double(b), suitable(fp, at: p, layer, lm) else { continue }
                    guard reachable(p, from: o, layer) else { continue }
                    let mp = MapPlacement(id: PlacementID(r.id), kind: PlacementKind(r.kind ?? "settlement"),
                                          templateID: r.poi.rawValue, anchor: p, footprint: fp, isDiscovered: false)
                    if layer.placements.place(mp) {
                        placed = true
                        break
                    }
                }
            }
        }
    }

    static func suitable(_ fp: TileFootprint, at p: GridPoint, _ layer: MapLayer, _ lm: Landmarks) -> Bool {
        for c in fp.cells(at: p) {
            guard let b = layer.terrain.biome(at: c), !b.isWet, b != .rock, !lm.base.contains(c),
                  layer.placements.canPlace(.single, at: c) else { return false }
        }
        return true
    }

    static func reachable(_ p: GridPoint, from o: GridPoint, _ layer: MapLayer) -> Bool {
        Pathfinder.route(in: layer, from: o, to: p, costs: .original, options: PathOptions(fog: .ignore)).path != nil
    }
}
