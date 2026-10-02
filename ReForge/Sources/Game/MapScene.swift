import SwiftUI
import ReForgeEngine

extension RGB {
    var color: Color { Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255) }
}

/// 1 フレームぶんの地図の絵の材料(値だけ)。Canvas の描画はこれだけを見る。
///
/// 描き方(order.md §5.5): 黒地に色つきの文字。1 マス = 1 文字を固定の正方形の枠の中央に描く
/// (文字の送り幅に依存しないので、全角・半角・曖昧幅の問題が起きない)。
/// 霧: 未踏は黒・既知は暗い地形だけ・視界の中(MapView.vision の円)は明るく、物と生き物も。
/// 速さ: 画面に映るマスだけを描き、同じ文字と色の組は 1 フレームに 1 回だけ文字を組む。
struct MapScene {
    var camera: MapCamera
    var map: MapView
    var chunks: [Int: MapChunk]
    var actors: [ActorSprite]
    var placements: [PlacementSprite]
    var route: [GridPoint]
    var night: Bool
    /// Frame を受け取ってからの秒(補間)。
    var elapsed: Double
    var terrains: [TerrainID: TerrainDef]
    /// 置くモードの照準(U18)。
    var preview: PlacementPreview? = nil
    /// 戦闘の場所(U18)。
    var battles: [GridPoint] = []

    private struct GlyphKey: Hashable {
        var glyph: String
        var color: RGB
    }

    func draw(_ ctx: inout GraphicsContext, size: CGSize) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
        let view = ScreenSize(width: Double(size.width), height: Double(size.height))
        let cs = camera.cellSize
        let font = Font.custom(FontBook.mapFont, fixedSize: cs * 0.78)
        var styles: [String: TileStyle] = [:]
        var texts: [GlyphKey: GraphicsContext.ResolvedText] = [:]

        func style(_ tint: String) -> TileStyle {
            if let s = styles[tint] { return s }
            let s = TilePalette.style(tint, terrains: terrains)
            styles[tint] = s
            return s
        }
        func text(_ glyph: String, _ color: RGB) -> GraphicsContext.ResolvedText {
            let key = GlyphKey(glyph: glyph, color: color)
            if let t = texts[key] { return t }
            let t = ctx.resolve(Text(verbatim: glyph).font(font).foregroundColor(color.color))
            texts[key] = t
            return t
        }
        func cellRect(_ p: GridPoint) -> CGRect {
            let o = camera.screenOrigin(of: p, in: view)
            return CGRect(x: o.x, y: o.y, width: cs, height: cs)
        }

        // 視界の円(行ごとの範囲)
        var spans: [Int: [ClosedRange<Int>]] = [:]
        for v in map.vision {
            for s in v.rowSpans where s.maxX >= s.minX { spans[s.y, default: []].append(s.minX...s.maxX) }
        }
        func isVisible(_ p: GridPoint) -> Bool { spans[p.y]?.contains { $0.contains(p.x) } ?? false }

        let r = camera.visibleCells(in: view)
        let x0 = max(0, r.origin.x), x1 = min(map.size.width, r.origin.x + r.size.width)
        let y0 = max(0, r.origin.y), y1 = min(map.size.height, r.origin.y + r.size.height)
        let lit = night ? TilePalette.nightVisible : 1.0
        let hint = TilePalette.style(TilePalette.hint, terrains: terrains).foreground(at: GridPoint(0, 0))

        // 地形
        if x0 < x1, y0 < y1 {
            for y in y0..<y1 {
                for x in x0..<x1 {
                    let p = GridPoint(x, y)
                    guard let ci = map.chunkIndex(of: p), let tile = chunks[ci]?.tile(at: p) else { continue }
                    let visible = isVisible(p)
                    let rect = cellRect(p)
                    let center = CGPoint(x: rect.midX, y: rect.midY)
                    var k = lit
                    if !visible {
                        switch tile.fog {
                        case .unknown, .visible:
                            continue
                        case .hint:
                            if let s = tile.shadow {
                                let t = text(s, hint)
                                ctx.draw(t, at: center, anchor: .center)
                            }
                            continue
                        case .remembered:
                            k = TilePalette.remembered
                        }
                    }
                    let st = style(tile.tint)
                    if let bg = st.background { ctx.fill(Path(rect), with: .color(bg.scaled(k).color)) }
                    let t = text(tile.glyph, st.foreground(at: p).scaled(k))
                    ctx.draw(t, at: center, anchor: .center)
                }
            }
        }

        // 歩く経路(点線)
        let routeColor = style(TilePalette.route).foreground(at: GridPoint(0, 0))
        for p in route where p.x >= x0 && p.x < x1 && p.y >= y0 && p.y < y1 {
            let rect = cellRect(p)
            ctx.fill(Path(rect), with: .color(.black))
            let t = text("・", routeColor)
            ctx.draw(t, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
        }

        // 置いた物
        for pl in placements {
            let rect = cellRect(pl.at)
            guard rect.maxX >= 0, rect.minX <= size.width, rect.maxY >= 0, rect.minY <= size.height else { continue }
            let k = isVisible(pl.at) ? lit : TilePalette.remembered
            let c = style(pl.running ? TilePalette.module : TilePalette.stopped).foreground(at: pl.at).scaled(k)
            ctx.fill(Path(rect), with: .color(.black))
            let t = text(pl.glyph, c)
            ctx.draw(t, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
        }

        // 戦闘の場所: 赤い枠(帯と同じ相手。止めない)
        for b in battles {
            let rect = cellRect(b).insetBy(dx: -cs * 0.5, dy: -cs * 0.5)
            ctx.stroke(Path(rect), with: .color(InkColor.alert), lineWidth: 2)
        }

        // 人(ノアを一番上に)。前のマスと次のマスの間を補間する。
        for a in actors.sorted(by: { !$0.isNoah && $1.isNoah }) {
            let pos = a.position(elapsed: elapsed)
            let c = camera.screen(pos, in: view)
            guard c.x > -cs, c.x < Double(size.width) + cs, c.y > -cs, c.y < Double(size.height) + cs else { continue }
            let rect = CGRect(x: c.x - cs / 2, y: c.y - cs / 2, width: cs, height: cs)
            ctx.fill(Path(rect), with: .color(.black))
            let color = style(a.tint).foreground(at: GridPoint(0, 0))
            let t = text(a.glyph, color)
            ctx.draw(t, at: CGPoint(x: c.x, y: c.y), anchor: .center)
        }

        // 置くモードの照準: 置けるなら緑、置けないなら赤。占めるマスを塗り、外枠を引く
        if let pv = preview {
            let color = pv.placeable ? InkColor.good : InkColor.alert
            for c in pv.cells {
                let rect = cellRect(c)
                ctx.fill(Path(rect), with: .color(color.opacity(0.28)))
                ctx.stroke(Path(rect.insetBy(dx: 1, dy: 1)), with: .color(color), lineWidth: 2)
            }
        }
    }
}
