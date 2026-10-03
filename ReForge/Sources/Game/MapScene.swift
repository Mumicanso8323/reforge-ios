import SwiftUI
import UIKit
import ReForgeEngine

extension RGB {
    var color: Color { Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255) }
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

    func image(for chunk: MapChunk, cellSize: Double, night: Bool, vision: [VisionArea], terrains: [TerrainID: TerrainDef]) -> Image? {
        let key = TerrainImageKey(index: chunk.index, revision: chunk.revision, cellSize: Int(cellSize), night: night, vision: vision)
        if let image = images[key] { return image }
        let view = TerrainChunkImage(chunk: chunk, cellSize: cellSize, night: night, vision: vision, terrains: terrains)
            .frame(width: Double(chunk.rect.size.width) * cellSize, height: Double(chunk.rect.size.height) * cellSize)
        let renderer = ImageRenderer(content: view)
        renderer.scale = UIScreen.main.scale
        guard let rendered = renderer.uiImage else { return nil }
        let image = Image(uiImage: rendered)
        images[key] = image
        renderCount[chunk.index, default: 0] += 1
        return image
    }

    func discardOutside(_ indices: Set<Int>) {
        images = images.filter { indices.contains($0.key.index) }
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
    var terrains: [TerrainID: TerrainDef]
    var preview: PlacementPreview? = nil
    var battles: [GridPoint] = []
    var beacons: [GridPoint] = []

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
            guard let chunk = chunks[index], let image = cache.image(for: chunk, cellSize: camera.cellSize, night: night,
                                                                       vision: map.vision, terrains: terrains) else { continue }
            let origin = camera.screenOrigin(of: chunk.rect.origin, in: view)
            let rect = CGRect(x: origin.x, y: origin.y, width: Double(chunk.rect.size.width) * camera.cellSize,
                              height: Double(chunk.rect.size.height) * camera.cellSize)
            ctx.draw(image, in: rect)
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
        let visible = camera.visibleCells(in: view)
        let x0 = max(0, visible.origin.x), x1 = min(map.size.width, visible.origin.x + visible.size.width)
        let y0 = max(0, visible.origin.y), y1 = min(map.size.height, visible.origin.y + visible.size.height)
        func isVisible(_ point: GridPoint) -> Bool { map.vision.contains { $0.contains(point) } }
        let lit = night ? TilePalette.nightVisible : 1.0

        let routeColor = style(TilePalette.route).foreground(at: GridPoint(0, 0))
        for point in route where point.x >= x0 && point.x < x1 && point.y >= y0 && point.y < y1 {
            let rect = cellRect(point)
            ctx.fill(Path(rect), with: .color(.black))
            ctx.draw(text("・", routeColor), at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
        }
        for placement in placements {
            let rect = cellRect(placement.at)
            guard rect.maxX >= 0, rect.minX <= size.width, rect.maxY >= 0, rect.minY <= size.height else { continue }
            let brightness = isVisible(placement.at) ? lit : TilePalette.remembered
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
            ctx.draw(text(actor.glyph, style(actor.tint).foreground(at: GridPoint(0, 0))), at: CGPoint(x: center.x, y: center.y), anchor: .center)
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
