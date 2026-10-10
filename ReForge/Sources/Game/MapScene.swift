import SwiftUI
import UIKit
import ReForgeEngine

extension RGB {
    var color: Color { Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255) }
}

/// 歩ける範囲の外周。マスごとの辺を連結して、内側の線を作らない。
enum WalkEdge {
    struct Segment: Equatable, Sendable {
        var from: GridPoint
        var to: GridPoint
    }

    static func segments(spans: [WalkSpan]) -> [Segment] {
        var cells: Set<GridPoint> = []
        for span in spans where span.minX <= span.maxX {
            for x in span.minX...span.maxX { cells.insert(GridPoint(x, span.y)) }
        }
        guard !cells.isEmpty else { return [] }

        var horizontal: [Int: [Int]] = [:]
        var vertical: [Int: [Int]] = [:]
        for cell in cells {
            if !cells.contains(GridPoint(cell.x, cell.y - 1)) { horizontal[cell.y, default: []].append(cell.x) }
            if !cells.contains(GridPoint(cell.x, cell.y + 1)) { horizontal[cell.y + 1, default: []].append(cell.x) }
            if !cells.contains(GridPoint(cell.x - 1, cell.y)) { vertical[cell.x, default: []].append(cell.y) }
            if !cells.contains(GridPoint(cell.x + 1, cell.y)) { vertical[cell.x + 1, default: []].append(cell.y) }
        }

        func runs(_ points: [Int]) -> [(Int, Int)] {
            let sorted = points.sorted()
            guard var first = sorted.first else { return [] }
            var last = first
            var output: [(Int, Int)] = []
            for point in sorted.dropFirst() {
                if point == last + 1 {
                    last = point
                } else {
                    output.append((first, last))
                    first = point
                    last = point
                }
            }
            output.append((first, last))
            return output
        }

        var output: [Segment] = []
        for y in horizontal.keys.sorted() {
            for (first, last) in runs(horizontal[y] ?? []) {
                output.append(Segment(from: GridPoint(first, y), to: GridPoint(last + 1, y)))
            }
        }
        for x in vertical.keys.sorted() {
            for (first, last) in runs(vertical[x] ?? []) {
                output.append(Segment(from: GridPoint(x, first), to: GridPoint(x, last + 1)))
            }
        }
        return output
    }
}

/// 同じ範囲なら外周を作り直さない。MapScene は描画だけを受け持つ。
@MainActor
final class WalkEdgeCache {
    private var previous: [WalkSpan] = []
    private var cached: [WalkEdge.Segment] = []

    func segments(for spans: [WalkSpan]) -> [WalkEdge.Segment] {
        guard spans != previous else { return cached }
        previous = spans
        cached = WalkEdge.segments(spans: spans)
        return cached
    }
}

/// 置いた印の明るさ。暗がりの印は、視界の外でも夜の見える段でゆっくり明滅する。
enum PlacementBrightness {
    static func value(seenInDark: Bool, visible: Bool, night: Bool, reduceMotion: Bool, elapsed: Double) -> Double {
        let base: Double
        if visible {
            base = night ? TilePalette.nightVisible : 1
        } else if seenInDark {
            base = TilePalette.nightVisible
        } else {
            base = TilePalette.remembered
        }
        guard seenInDark, !reduceMotion else { return base }
        return base * (1 + 0.15 * sin(elapsed * 2 * .pi / 3))
    }
}

private struct TerrainImageKey: Hashable {
    var index: Int
    var revision: Int
    var cellSize: Int
    var night: Bool
    var vision: [VisionArea]
}

/// 見えている区画とその周囲だけを画像で持つ。`renderCount` は回帰試験用。
@MainActor
final class MapTerrainCache {
    private var images: [TerrainImageKey: Image] = [:]
    private(set) var renderCount: [Int: Int] = [:]
    /// 画が作れなかった(nil、または見える物があるのに全部透明)鍵と、その実時刻。しばらくは作り直さず、呼び出し側がその場で描く。
    private var failedAt: [TerrainImageKey: TimeInterval] = [:]
    /// 作り直しを待つ秒数(画を作る重い処理を毎フレーム繰り返さない)。
    static let retryAfter: TimeInterval = 1.0
    /// 画が作れなかった回数と、呼び出し側がその場で描いた回数。
    private(set) var renderFailures = 0
    private(set) var fallbackDraws = 0

    func image(for chunk: MapChunk, cellSize: Double, night: Bool, vision: [VisionArea], terrains: [TerrainID: TerrainDef]) -> Image? {
        let key = TerrainImageKey(index: chunk.index, revision: chunk.revision, cellSize: Int(cellSize), night: night, vision: vision)
        if let image = images[key] { return image }
        let now = ProcessInfo.processInfo.systemUptime
        if let failed = failedAt[key], now - failed < Self.retryAfter { return directDrawn() }
        let view = TerrainChunkImage(chunk: chunk, cellSize: cellSize, night: night, vision: vision, terrains: terrains)
            .frame(width: Double(chunk.rect.size.width) * cellSize, height: Double(chunk.rect.size.height) * cellSize)
        let renderer = ImageRenderer(content: view)
        renderer.scale = UIScreen.main.scale
        // nil、または「見える物があるのに全部透明」の画(描画の一瞬の失敗)は、キャッシュに入れず作り直す。
        // 透明な画を鍵ごと覚えると、視界の鍵が変わるまで地形が黒いまま居座る。
        let expectsInk = chunk.tiles.contains { $0.fog == .remembered || $0.fog == .visible }
        guard let rendered = renderer.uiImage else {
            renderFailures += 1
#if DEBUG
            ReplayStats.renderFailures += 1
#endif
            failedAt[key] = now
            return directDrawn()
        }
        if expectsInk, !Self.hasInk(rendered) {
#if DEBUG
            ReplayStats.blankRenders += 1
#endif
            failedAt[key] = now
            return directDrawn()
        }
        let image = Image(uiImage: rendered)
        images[key] = image
        failedAt[key] = nil
        renderCount[chunk.index, default: 0] += 1
        return image
    }

    /// 画が作れなかった時は nil を返し、呼び出し側(MapScene.drawTerrain)がその区画をその場の Canvas に直接描く。
    private func directDrawn() -> Image? {
        fallbackDraws += 1
#if DEBUG
        ReplayStats.fallbackDraws += 1
#endif
        return nil
    }

    /// 画に 1 画素でも透明でない所があるか(小さく縮めた α だけの表で見る)。
    private static func hasInk(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return true }
        let side = 48
        var buffer = [UInt8](repeating: 0, count: side * side)
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return false }
            ctx.interpolationQuality = .high
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return !drawn || buffer.contains { $0 > 0 }
    }

    func discardOutside(_ indices: Set<Int>) {
        images = images.filter { indices.contains($0.key.index) }
        failedAt = failedAt.filter { indices.contains($0.key.index) }
    }
}

/// 1 区画の静かな絵。ここでだけ地形の文字を resolve し、同じ鍵なら再び組まない。
private struct TerrainChunkImage: View {
    let chunk: MapChunk
    let cellSize: Double
    let night: Bool
    let vision: [VisionArea]
    let terrains: [TerrainID: TerrainDef]

    private struct GlyphKey: Hashable { var glyph: String; var color: RGB }

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { ctx, _ in
            var ctx = ctx
            Self.paint(&ctx, chunk: chunk, cellSize: cellSize, night: night, vision: vision, terrains: terrains)
        }
    }

    /// 区画を、原点を区画の左上に置いた描画先へ描く。画にする時も、画が作れなかった時にその場で描く時も、これ 1 本。
    static func paint(_ ctx: inout GraphicsContext, chunk: MapChunk, cellSize: Double, night: Bool, vision: [VisionArea],
                      terrains: [TerrainID: TerrainDef]) {
        let font = Font.custom(FontBook.mapFont, fixedSize: cellSize * 0.78)
        var styles: [String: TileStyle] = [:]
        var texts: [GlyphKey: GraphicsContext.ResolvedText] = [:]
        func style(_ tint: String) -> TileStyle {
            if let style = styles[tint] { return style }
            let style = TilePalette.style(tint, terrains: terrains)
            styles[tint] = style
            return style
        }
        func text(_ glyph: String, _ color: RGB) -> GraphicsContext.ResolvedText {
            let key = GlyphKey(glyph: glyph, color: color)
            if let text = texts[key] { return text }
            let text = ctx.resolve(Text(verbatim: glyph).font(font).foregroundColor(color.color))
            texts[key] = text
            return text
        }
        let lit = night ? TilePalette.nightVisible : 1.0
        let hint = TilePalette.style(TilePalette.hint, terrains: terrains).foreground(at: GridPoint(0, 0))
        for y in chunk.rect.origin.y..<(chunk.rect.origin.y + chunk.rect.size.height) {
            for x in chunk.rect.origin.x..<(chunk.rect.origin.x + chunk.rect.size.width) {
                let point = GridPoint(x, y)
                guard let tile = chunk.tile(at: point) else { continue }
                let rect = CGRect(x: Double(x - chunk.rect.origin.x) * cellSize,
                                  y: Double(y - chunk.rect.origin.y) * cellSize, width: cellSize, height: cellSize)
                var brightness = lit
                if tile.glow, tile.fog != .unknown {
                    brightness = 1
                } else if !vision.contains(where: { $0.contains(point) }) {
                    switch tile.fog {
                    case .unknown, .visible: continue
                    case .hint:
                        if let shadow = tile.shadow { ctx.draw(text(shadow, hint), at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center) }
                        continue
                    case .remembered: brightness = TilePalette.remembered
                    }
                }
                let tileStyle = style(tile.tint)
                if let background = tileStyle.background { ctx.fill(Path(rect), with: .color(background.scaled(brightness).color)) }
                ctx.draw(text(tile.glyph, tileStyle.foreground(at: point).scaled(brightness)), at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
            }
        }
    }
}

/// 1 フレームぶんの地図の絵の材料。地形と動くものを別の Canvas で描く。
@MainActor
struct MapScene {
    var camera: MapCamera
    var map: MapView
    var chunks: [Int: MapChunk]
    var actors: [ActorSprite]
    var placements: [PlacementSprite]
    var route: [GridPoint]
    var night: Bool
    var elapsed: Double
    var reduceMotion: Bool = false
    var terrains: [TerrainID: TerrainDef]
    var preview: PlacementPreview? = nil
    var battles: [GridPoint] = []
    var beacons: [GridPoint] = []
    /// タップで選んだマス。経路とは別の角印で示す。
    var selected: GridPoint? = nil
    /// 歩ける範囲の外周。MapCanvasView のキャッシュ済みの形を受け取る。
    var walkEdges: [WalkEdge.Segment] = []

    private struct GlyphKey: Hashable { var glyph: String; var color: RGB }

    func drawTerrain(_ ctx: inout GraphicsContext, size: CGSize, cache: MapTerrainCache) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
        let view = ScreenSize(width: Double(size.width), height: Double(size.height))
        let visible = camera.visibleCells(in: view)
        let padded = GridRect(origin: GridPoint(visible.origin.x - MapView.chunkSize, visible.origin.y - MapView.chunkSize),
                              size: GridSize(width: visible.size.width + 2 * MapView.chunkSize, height: visible.size.height + 2 * MapView.chunkSize))
        let retained = Set(map.chunks(overlapping: padded))
        cache.discardOutside(retained)
        for index in map.chunks(overlapping: visible) {
            guard let chunk = chunks[index] else { continue }
            let origin = camera.screenOrigin(of: chunk.rect.origin, in: view)
            let rect = CGRect(x: origin.x, y: origin.y, width: Double(chunk.rect.size.width) * camera.cellSize,
                              height: Double(chunk.rect.size.height) * camera.cellSize)
            if let image = cache.image(for: chunk, cellSize: camera.cellSize, night: night, vision: map.vision, terrains: terrains) {
                ctx.draw(image, in: rect)
            } else {
                // 区画の画が作れなかった時(遅くても、黒よりよい): その場の Canvas に同じ描き方で直接描く
                var sub = ctx
                sub.clip(to: Path(rect))
                sub.translateBy(x: rect.minX, y: rect.minY)
                TerrainChunkImage.paint(&sub, chunk: chunk, cellSize: camera.cellSize, night: night, vision: map.vision, terrains: terrains)
            }
        }
    }

    func drawMoving(_ ctx: inout GraphicsContext, size: CGSize) {
        let view = ScreenSize(width: Double(size.width), height: Double(size.height))
        let cellSize = camera.cellSize
        let font = Font.custom(FontBook.mapFont, fixedSize: cellSize * 0.78)
        var styles: [String: TileStyle] = [:]
        var texts: [GlyphKey: GraphicsContext.ResolvedText] = [:]
        func style(_ tint: String) -> TileStyle {
            if let style = styles[tint] { return style }
            let style = TilePalette.style(tint, terrains: terrains)
            styles[tint] = style
            return style
        }
        func text(_ glyph: String, _ color: RGB) -> GraphicsContext.ResolvedText {
            let key = GlyphKey(glyph: glyph, color: color)
            if let text = texts[key] { return text }
            let text = ctx.resolve(Text(verbatim: glyph).font(font).foregroundColor(color.color))
            texts[key] = text
            return text
        }
        func cellRect(_ point: GridPoint) -> CGRect {
            let origin = camera.screenOrigin(of: point, in: view)
            return CGRect(x: origin.x, y: origin.y, width: cellSize, height: cellSize)
        }
        if !walkEdges.isEmpty {
            var edgePath = Path()
            for edge in walkEdges {
                let from = camera.screenOrigin(of: edge.from, in: view)
                let to = camera.screenOrigin(of: edge.to, in: view)
                edgePath.move(to: CGPoint(x: from.x, y: from.y))
                edgePath.addLine(to: CGPoint(x: to.x, y: to.y))
            }
            ctx.stroke(edgePath, with: .color(InkColor.accent.opacity(0.6)), lineWidth: 1.5)
        }
        let visible = camera.visibleCells(in: view)
        let x0 = max(0, visible.origin.x), x1 = min(map.size.width, visible.origin.x + visible.size.width)
        let y0 = max(0, visible.origin.y), y1 = min(map.size.height, visible.origin.y + visible.size.height)
        func isVisible(_ point: GridPoint) -> Bool { map.vision.contains { $0.contains(point) } }
        let routeColor = style(TilePalette.route).foreground(at: GridPoint(0, 0))
        for point in route where point.x >= x0 && point.x < x1 && point.y >= y0 && point.y < y1 {
            let rect = cellRect(point)
            ctx.fill(Path(rect), with: .color(.black))
            ctx.draw(text("・", routeColor), at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
        }
        if let selected, selected.x >= x0 && selected.x < x1 && selected.y >= y0 && selected.y < y1 {
            let rect = cellRect(selected).insetBy(dx: 2, dy: 2)
            let color = InkColor.accent
            let corner: CGFloat = min(7, cellSize * 0.28)
            var path = Path()
            path.move(to: CGPoint(x: rect.minX + corner, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + corner))
            path.move(to: CGPoint(x: rect.maxX - corner, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - corner))
            ctx.stroke(path, with: .color(color), lineWidth: 2)
        }

        for placement in placements {
            let rect = cellRect(placement.at)
            guard rect.maxX >= 0, rect.minX <= size.width, rect.maxY >= 0, rect.minY <= size.height else { continue }
            let brightness = PlacementBrightness.value(seenInDark: placement.seenInDark, visible: isVisible(placement.at),
                                                        night: night, reduceMotion: reduceMotion, elapsed: elapsed)
            let color = style(placement.running ? TilePalette.module : TilePalette.stopped).foreground(at: placement.at).scaled(brightness)
            ctx.fill(Path(rect), with: .color(.black))
            ctx.draw(text(placement.glyph, color), at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
        }
        for beacon in beacons where beacon.x >= x0 && beacon.x < x1 && beacon.y >= y0 && beacon.y < y1 {
            let rect = cellRect(beacon)
            ctx.fill(Path(ellipseIn: rect.insetBy(dx: cellSize * 0.3, dy: cellSize * 0.3)), with: .color(RGB(240, 230, 170).color))
        }
        for battle in battles {
            ctx.stroke(Path(cellRect(battle).insetBy(dx: -cellSize * 0.5, dy: -cellSize * 0.5)), with: .color(InkColor.alert), lineWidth: 2)
        }
        for actor in actors.sorted(by: { !$0.isNoah && $1.isNoah }) {
            let position = actor.position(elapsed: elapsed)
            let center = camera.screen(position, in: view)
            guard center.x > -cellSize, center.x < Double(size.width) + cellSize,
                  center.y > -cellSize, center.y < Double(size.height) + cellSize else { continue }
            let rect = CGRect(x: center.x - cellSize / 2, y: center.y - cellSize / 2, width: cellSize, height: cellSize)
            ctx.fill(Path(rect), with: .color(.black))
            let actorColor = style(actor.tint).foreground(at: GridPoint(0, 0))
            ctx.draw(text(actor.glyph, actorColor), at: CGPoint(x: center.x, y: center.y), anchor: .center)
            if actor.isMember {
                let c = center
                let cs = cellSize
                let triangle = Path { p in
                    let s = cs * 0.12
                    switch actor.facing {
                    case .north:
                        p.move(to: CGPoint(x: c.x, y: c.y - cs * 0.34)); p.addLine(to: CGPoint(x: c.x - s, y: c.y - cs * 0.16)); p.addLine(to: CGPoint(x: c.x + s, y: c.y - cs * 0.16))
                    case .south:
                        p.move(to: CGPoint(x: c.x, y: c.y + cs * 0.34)); p.addLine(to: CGPoint(x: c.x - s, y: c.y + cs * 0.16)); p.addLine(to: CGPoint(x: c.x + s, y: c.y + cs * 0.16))
                    case .east:
                        p.move(to: CGPoint(x: c.x + cs * 0.34, y: c.y)); p.addLine(to: CGPoint(x: c.x + cs * 0.16, y: c.y - s)); p.addLine(to: CGPoint(x: c.x + cs * 0.16, y: c.y + s))
                    case .west:
                        p.move(to: CGPoint(x: c.x - cs * 0.34, y: c.y)); p.addLine(to: CGPoint(x: c.x - cs * 0.16, y: c.y - s)); p.addLine(to: CGPoint(x: c.x - cs * 0.16, y: c.y + s))
                    }
                    p.closeSubpath()
                }
                ctx.fill(triangle, with: .color(actorColor.color))
            }
        }
        if let preview {
            let color = preview.placeable ? InkColor.good : InkColor.alert
            for cell in preview.cells {
                let rect = cellRect(cell)
                ctx.fill(Path(rect), with: .color(color.opacity(0.28)))
                ctx.stroke(Path(rect.insetBy(dx: 1, dy: 1)), with: .color(color), lineWidth: 2)
            }
        }
    }
}
