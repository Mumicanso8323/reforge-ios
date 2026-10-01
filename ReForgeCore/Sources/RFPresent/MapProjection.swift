import RFContent
import RFKernel
import RFMap
import RFPerception
import RFWorld

/// 画面だけが使う見出し(認識の表のキー)。RFContent の Subject に無い名前空間。
/// U3 が Subject に足したらそちらを使う。
public enum PresentSubject {
    /// 鉱脈の見た目(「赤褐色の岩脈」)。真実の鉱石の名前とは別の見出し。
    public static func deposit(_ ore: ItemID) -> SubjectID { SubjectID("deposit:\(ore.rawValue)") }
    /// マス・目印・置いた物に対する行為の名前(足元カードのボタン)。
    public static func interaction(_ id: InteractionID) -> SubjectID { SubjectID("interaction:\(id.rawValue)") }
}

/// 地図 1 層の見え方を引く係(Frame を作るたびに 1 つ作る)。
///
/// 霧の 3 状態: 未踏は黒・既知は暗い地形だけ・視界の中は明るく物と生き物も(視界は MapView.vision)。
/// 霧の端の手がかり: 未踏のマスでも、目印(残骸など)が既知のマスから 2 マス以内なら影を出す
/// (目印の起点のマスは「？」、ほかのマスは目印の文字の影)。
struct MapProjector {
    static let hintReach = 2

    let layerID: LayerID
    let layer: MapLayer?
    let known: GridBitset?
    let perceiver: Perceiver
    let content: ContentDB
    /// マス → 目印(起点のマスか)。
    let poiAt: [GridPoint: (id: EntityID, poi: POIState, anchor: Bool)]
    let depositAt: [GridPoint: (id: EntityID, deposit: DepositState)]
    /// 地形の添字 → 文字(認識の層を毎マス引かないように先に引く)。
    let terrainGlyphs: [String]

    init(world w: WorldState, content: ContentDB, perceiver: Perceiver, layer layerID: LayerID) {
        self.layerID = layerID
        self.layer = w.map[layerID]
        self.known = w.knowledge.mapKnown[layerID]
        self.perceiver = perceiver
        self.content = content
        var pa: [GridPoint: (id: EntityID, poi: POIState, anchor: Bool)] = [:]
        var da: [GridPoint: (id: EntityID, deposit: DepositState)] = [:]
        if let l = layer {
            for id in l.pois.keys.sorted() {
                guard let poi = l.pois[id] else { continue }
                for off in poi.footprint {
                    let pt = GridPoint(poi.at.x + off.x, poi.at.y + off.y)
                    if pa[pt] == nil { pa[pt] = (id, poi, off == GridPoint(0, 0)) }
                }
            }
            for id in l.deposits.keys.sorted() {
                guard let d = l.deposits[id], da[d.at] == nil else { continue }
                da[d.at] = (id, d)
            }
        }
        self.poiAt = pa
        self.depositAt = da
        self.terrainGlyphs = (layer?.palette ?? []).map { t in
            perceiver.variant(Subject.terrain(t))?.glyph ?? content.glyphs[Subject.terrain(t)] ?? "？"
        }
    }

    var size: GridSize { layer?.size ?? GridSize(width: 0, height: 0) }

    func isKnown(_ p: GridPoint) -> Bool { known?[p] ?? false }

    /// 未踏の目印のマスで、既知のマスが近くにあるか。
    func isHint(_ p: GridPoint) -> Bool {
        guard poiAt[p] != nil, !isKnown(p), known != nil else { return false }
        let r = Self.hintReach
        for dy in -r...r { for dx in -r...r where isKnown(GridPoint(p.x + dx, p.y + dy)) { return true } }
        return false
    }

    /// 1 マスの見え方(視界によらない部分)。
    func tile(_ p: GridPoint) -> TileView {
        guard let l = layer, size.contains(p) else { return .void }
        let fog: TileView.Fog = isKnown(p) ? .remembered : (isHint(p) ? .hint : .unknown)
        var glyph: String
        var tint: String
        if let poi = poiAt[p] {
            glyph = poiGlyph(poi.poi.kind)
            tint = TilePalette.poi
        } else if let d = depositAt[p], d.deposit.remainingExtractions > 0 {
            glyph = perceiver.variant(PresentSubject.deposit(d.deposit.ore))?.glyph
                ?? content.glyphs[PresentSubject.deposit(d.deposit.ore)] ?? "晶"
            tint = TilePalette.deposit(d.deposit.ore)
        } else {
            let i = Int(l.terrain[size.index(p)])
            glyph = TilePalette.pickGlyph(i < terrainGlyphs.count ? terrainGlyphs[i] : "？", at: p)
            tint = l.terrain(at: p).map(TilePalette.terrain) ?? TilePalette.void
        }
        var shadow: String?
        if fog == .hint, let poi = poiAt[p] { shadow = poi.anchor ? "？" : poiGlyph(poi.poi.kind) }
        return TileView(glyph: glyph, tint: tint, fog: fog, shadow: shadow)
    }

    func poiGlyph(_ kind: POIKindID) -> String {
        perceiver.variant(Subject.poi(kind))?.glyph ?? content.glyphs[Subject.poi(kind)] ?? "▒"
    }

    /// 区画の中身の指紋(地形・既知・手がかり・目印・鉱脈)。見え方の文字は事実が変わったときに全区画を上げるので入れない。
    func signature(_ r: GridRect) -> Int {
        guard let l = layer else { return 0 }
        var h = Hasher()
        for y in r.origin.y..<(r.origin.y + r.size.height) {
            for x in r.origin.x..<(r.origin.x + r.size.width) {
                let p = GridPoint(x, y)
                h.combine(l.terrain[size.index(p)])
                h.combine(isKnown(p))
                if let poi = poiAt[p] {
                    h.combine(poi.id)
                    h.combine(isHint(p))
                }
                if let d = depositAt[p] { h.combine(d.id); h.combine(d.deposit.remainingExtractions > 0) }
            }
        }
        return h.finalize()
    }

    func chunk(_ index: Int, map: MapView) -> MapChunk {
        let r = map.chunkRect(index)
        var tiles: [TileView] = []
        tiles.reserveCapacity(r.size.count)
        for y in r.origin.y..<(r.origin.y + r.size.height) {
            for x in r.origin.x..<(r.origin.x + r.size.width) { tiles.append(tile(GridPoint(x, y))) }
        }
        let rev = index < map.chunkRevisions.count ? map.chunkRevisions[index] : 0
        return MapChunk(index: index, revision: rev, rect: r, tiles: tiles)
    }
}
