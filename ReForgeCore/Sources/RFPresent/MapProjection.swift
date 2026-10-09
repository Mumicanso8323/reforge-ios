import RFContent
import RFExploration
import RFKernel
import RFMap
import RFPerception
import RFWorld

/// 画面だけが使う見出し(認識の表のキー)。RFContent の Subject に無い名前空間。
/// U3 が Subject に足したらそちらを使う。
public enum PresentSubject {
    /// 鉱脈の見た目の見出し「deposit:<種類>.<見た目の番号>」(U14 と合意)。真実の鉱石の名前とは別の見出し。
    public static func deposit(_ d: Deposit) -> SubjectID {
        SubjectID("deposit:\(d.category.rawValue).\(d.appearanceVariant)")
    }
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
    let depositAt: [GridPoint: (id: DepositID, deposit: Deposit)]
    /// 地形 → 文字(認識の層を毎マス引かないように先に引く)。
    let terrainGlyphs: [Biome: String]
    /// クールダウンのある地形の行為(使い切りの見た目の判定に使う。ID 順)。
    let cooldownTerrain: [(def: InteractionDef, tag: String)]
    let world: WorldState

    init(world w: WorldState, content: ContentDB, perceiver: Perceiver, layer layerID: LayerID) {
        self.layerID = layerID
        self.layer = w.map[layerID]
        self.known = w.knowledge.mapKnown[layerID]
        self.perceiver = perceiver
        self.content = content
        var pa: [GridPoint: (id: EntityID, poi: POIState, anchor: Bool)] = [:]
        var da: [GridPoint: (id: DepositID, deposit: Deposit)] = [:]
        if let l = layer {
            for id in l.pois.keys.sorted() {
                guard let poi = l.pois[id] else { continue }
                for off in poi.footprint {
                    let pt = GridPoint(poi.at.x + off.x, poi.at.y + off.y)
                    if pa[pt] == nil { pa[pt] = (id, poi, off == GridPoint(0, 0)) }
                }
            }
            for d in l.deposits.all where da[d.position] == nil {
                da[d.position] = (d.id, d)
            }
        }
        self.poiAt = pa
        self.depositAt = da
        var tg: [Biome: String] = [:]
        for b in Biome.allCases {
            let t = b.terrainID
            tg[b] = perceiver.variant(Subject.terrain(t))?.glyph ?? content.glyphs[Subject.terrain(t)] ?? "？"
        }
        self.terrainGlyphs = tg
        self.world = w
        self.cooldownTerrain = content.interactions.values.sorted { $0.id < $1.id }.compactMap { d in
            if case .terrain(let tag) = d.target, (d.cooldownDays ?? 0) > 0 { return (d, tag) }
            return nil
        }
    }

    /// そのマス(地形)が、採った後でまだ拾えない(クールダウン中)か。
    func isSpent(_ p: GridPoint, terrain t: TerrainID) -> Bool {
        guard !cooldownTerrain.isEmpty else { return false }
        let tags = content.terrains[t]?.tags ?? [t.rawValue]
        for (d, tag) in cooldownTerrain where tags.contains(tag) || t.rawValue == tag {
            if Interactions.isCoolingDown(d, at: WorldPoint(layerID, p), world: world) { return true }
        }
        return false
    }

    var size: GridSize { layer?.size ?? GridSize(width: 0, height: 0) }

    func isKnown(_ p: GridPoint) -> Bool { known?[p] ?? false }

    /// 未踏の目印のマスで、既知のマスが近くにあるか。
    func isHint(_ p: GridPoint) -> Bool {
        guard let poi = poiAt[p], !isKnown(p), known != nil else { return false }
        let r = landmarkRadius(poi.poi.kind) ?? Self.hintReach
        for dy in -r...r { for dx in -r...r where isKnown(GridPoint(p.x + dx, p.y + dy)) { return true } }
        return false
    }

    /// 1 マスの見え方(視界によらない部分)。
    func tile(_ p: GridPoint) -> TileView {
        guard let l = layer, size.contains(p) else { return .void }
        let fog: TileView.Fog = isKnown(p) ? .remembered : (isHint(p) ? .hint : .unknown)
        var glyph: String
        var tint: String
        var glow = false
        if let poi = poiAt[p] {
            let v = partSubject(poi.poi, at: p).flatMap { perceiver.variant($0) }
            glyph = v?.glyph ?? poiGlyph(poi.poi.kind)
            tint = TilePalette.poi
            glow = v?.glow ?? perceiver.variant(Subject.poi(poi.poi.kind))?.glow ?? false
        } else if let d = depositAt[p], d.deposit.remainingExtractions > 0 {
            let v = perceiver.variant(PresentSubject.deposit(d.deposit))
            glyph = v?.glyph ?? content.glyphs[PresentSubject.deposit(d.deposit)] ?? "晶"
            tint = TilePalette.deposit(d.deposit.category.rawValue)
            glow = v?.glow ?? false
        } else {
            glyph = TilePalette.pickGlyph(l.biome(at: p).flatMap { terrainGlyphs[$0] } ?? "？", at: p)
            tint = l.terrain(at: p).map(TilePalette.terrain) ?? TilePalette.void
            if let t = l.terrain(at: p), isSpent(p, terrain: t) {
                glyph = TilePalette.spentGlyph
                tint += TilePalette.spentSuffix
            }
        }
        var shadow: String?
        if fog == .hint, let poi = poiAt[p] {
            // 遠景(landmarkRadius)は起点も目印の影。ふつうの手がかりは起点が「？」
            shadow = poi.anchor && landmarkRadius(poi.poi.kind) == nil ? "？" : poiGlyph(poi.poi.kind)
        }
        if fog == .unknown { glow = false }
        return TileView(glyph: MapGlyphFont.safe(glyph), tint: tint, fog: fog, shadow: shadow.map(MapGlyphFont.safe), glow: glow)
    }

    /// 遠景の半径(POIDef.landmarkRadius)。
    func landmarkRadius(_ kind: POIKindID) -> Int? { content.pois[kind]?.landmarkRadius }

    /// マスに当たる有限の部品の見出し(part:<名前>。部品の見え方が認識の表にあるときだけ)。
    func partSubject(_ poi: POIState, at p: GridPoint) -> SubjectID? {
        guard let parts = content.pois[poi.kind]?.parts,
              let name = PlacementPartIndex.part(atOffset: p - poi.at, footprint: poi.footprint, parts: parts) else { return nil }
        let s = Subject.part(name)
        return content.perception[s] == nil ? nil : s
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
                h.combine(l.biome(at: p))
                h.combine(isKnown(p))
                if let poi = poiAt[p] {
                    h.combine(poi.id)
                    h.combine(isHint(p))
                }
                if let d = depositAt[p] { h.combine(d.id); h.combine(d.deposit.remainingExtractions > 0) }
                if poiAt[p] == nil, let t = l.terrain(at: p) { h.combine(isSpent(p, terrain: t)) }
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
