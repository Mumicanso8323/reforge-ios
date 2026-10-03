import SwiftUI
import ReForgeEngine

/// 主画面の地図(order.md §5.5)。
///
/// | 操作 | 指 | 結果 |
/// | 歩く | 同じマスを 2 度タップ | 1 度目は選び、2 度目で経路を点線で描いて歩き出す |
/// | 見回す | 1 本指のドラッグ | 視点だけ動く。追従が外れ、右下に「◎」(押すとノアに戻る) |
/// | 拡大・縮小 | ピンチ | 3 段にスナップ(既定は 1 マス 44pt)。中間の倍率は使わない |
/// | 調べる | 長押し | ふきだしで名前・鉱脈の見た目・残り回数・ノアの手ざわり |
///
/// タップ・長押し・ドラッグは 1 つの DragGesture(最小距離 0)で見分ける(長押しは押している間に 0.5 秒で出す)。
struct MapCanvasView: View {
    let store: GameStore
    let bandHeight: CGFloat
    @State private var camera = MapCamera()
    @State private var touch: Touch?
    @State private var pinchStartZoom: Int?
    @State private var longPressTask: Task<Void, Never>?
    @State private var terrainCache = MapTerrainCache()
    @State private var walkEdgeCache = WalkEdgeCache()
    @State private var autoReturnTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Touch {
        var start: CGPoint
        var last: CGPoint
        var panned = false
        var pinching = false
    }

    static let panThreshold: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let view = ScreenSize(width: Double(geo.size.width), height: Double(geo.size.height))
            // 地形は Frame または視点が変わったときだけ、動く層だけは歩いている間に補間する。
            let camera = liveCamera()
            let terrain = currentScene(camera: camera, elapsed: 0)
            let controlLift = BandOverlayLayout.controlLift(band: bandHeight, mapHeight: geo.size.height)
            ZStack {
                Canvas(opaque: true, rendersAsynchronously: false) { ctx, size in
                    terrain.drawTerrain(&ctx, size: size, cache: terrainCache)
                }
                TimelineView(.animation(minimumInterval: nil,
                                        paused: !store.actors.contains(where: \.isMoving)
                                            && (reduceMotion || !store.placements.contains(where: \.seenInDark)))) { _ in
                    let moving = currentScene(camera: camera, elapsed: elapsed)
                    Canvas(opaque: false, rendersAsynchronously: false) { ctx, size in
                        moving.drawMoving(&ctx, size: size)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(drag(view))
            .simultaneousGesture(pinch)
            .overlay(alignment: layout.mapControlAlignment(.left)) { zoomControls.padding(.bottom, controlLift) }
            .overlay(alignment: layout.mapControlAlignment()) { mapControls.padding(.bottom, controlLift) }
            .overlay(alignment: .top) { bubbles }
            .overlay(alignment: .bottom) { placingBar }
            .overlay(alignment: .bottom) { forgePanel }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("map")
        }
        .background(Color.black)
        .clipped()
        .onAppear {
            let plan = MapTouchSettings.zoomPlan()
            camera = MapCamera(center: camera.center, zoom: plan.defaultZoom, following: camera.following,
                               zoomLevels: plan.levels)
        }
    }

    // MARK: - 絵

    private var elapsed: Double { ProcessInfo.processInfo.systemUptime - store.frameTime }

    private var noahPosition: MapPointF? {
        store.actors.first(where: \.isNoah)?.position(elapsed: elapsed)
    }

    /// 追従中ならノアの補間した位置を中心にした視点。
    private func liveCamera() -> MapCamera {
        var c = camera
        if c.following {
            c.center = noahPosition ?? MapPointF(x: Double(store.mapView.size.width) / 2,
                                                 y: Double(store.mapView.size.height) / 2)
        }
        return c
    }

    private func currentScene(camera: MapCamera, elapsed: Double) -> MapScene {
        MapScene(camera: camera, map: store.mapView, chunks: store.chunks, actors: store.actors,
                 placements: store.placements, route: store.route, night: store.clock.isNight, elapsed: elapsed,
                 reduceMotion: reduceMotion, terrains: store.content.terrains, preview: store.preview, battles: store.battles.map(\.at),
                 beacons: store.mapView.beacons, selected: store.selected,
                 walkEdges: walkEdgeCache.segments(for: store.walkable))
    }

    private var layout: HUDLayout { .portrait(hand: MapTouchSettings.hand()) }

    // MARK: - 指

    private func drag(_ view: ScreenSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { v in
                if touch == nil {
                    touch = Touch(start: v.startLocation, last: v.startLocation)
                }
                guard var t = touch, !t.pinching else { return }
                let moved = hypot(v.location.x - t.start.x, v.location.y - t.start.y)
                if !t.panned, moved > Self.panThreshold {
                    t.panned = true
                    // 追従を外す: いま見えている中心から見回しを始める
                    camera.center = liveCamera().center
                    camera.following = false
                    autoReturnTask?.cancel()
                }
                if t.panned {
                    camera.pan(byScreen: Double(v.location.x - t.last.x), Double(v.location.y - t.last.y),
                               mapSize: store.mapView.size)
                    t.last = v.location
                }
                touch = t
            }
            .onEnded { v in
                defer { touch = nil }
                guard let t = touch, !t.pinching else { return }
                if t.panned {
                    store.logPlay(kind: "pan", fields: ["zone": "middle"])
                    scheduleAutoReturn()
                    return
                }
                let cell = liveCamera().cell(at: ScreenPoint(x: Double(v.location.x), y: Double(v.location.y)), in: view)
                store.logPlay(kind: "select", fields: ["x": "\(cell.x)", "y": "\(cell.y)", "zone": "middle"])
                if MapTouchSettings.defaults.bool(forKey: MapTouchSettings.tapWalkKey) {
                    store.select(cell)
                    store.walkToSelection()
                } else {
                    store.select(cell)
                }
            }
    }

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { v in
                if pinchStartZoom == nil {
                    pinchStartZoom = camera.zoom
                }
                if var t = touch {
                    t.pinching = true
                    touch = t
                }
                let z = MapCamera.snappedZoom(from: pinchStartZoom ?? camera.zoom, pinchScale: Double(v.magnification),
                                               levels: MapTouchSettings.zoomPlan().levels)
                if z != camera.zoom { camera.setZoom(z) }
            }
            .onEnded { _ in
                if let before = pinchStartZoom, before != camera.zoom {
                    store.logPlay(kind: "zoom", fields: ["level": "\(camera.zoom)", "source": "pinch", "zone": "middle"])
                }
                pinchStartZoom = nil
            }
    }

    // MARK: - 重ねるもの

    @ViewBuilder private var recenterButton: some View {
        if !camera.following {
            Button {
                if let n = noahPosition { camera.recenter(on: n) } else { camera.following = true }
                store.clearSelection()
            } label: {
                VStack(spacing: 0) {
                    Text(verbatim: TilePalette.noahGlyph)
                        .font(.custom(FontBook.mapFont, fixedSize: 22))
                    Text("戻る").font(InkFont.caption)
                }
                .foregroundStyle(Color(red: 1, green: 1, blue: 0.4))
                .frame(width: 48, height: 48)
                .background(Circle().fill(Color.black.opacity(0.75)))
                .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
            }
            .padding(12)
            .accessibilityLabel(Text("ノアに戻る"))
            .accessibilityIdentifier("recenterButton")
        }
    }

    private var mapControls: some View {
        Group {
            if MapTouchSettings.defaults.bool(forKey: MapTouchSettings.stickPlacementKey) {
                HStack(spacing: 10) {
                    recenterButton
                    if store.canSteer { StickControl(store: store, layout: layout) }
                }
            } else {
                VStack(spacing: 10) {
                    recenterButton
                    if store.canSteer { StickControl(store: store, layout: layout) }
                }
            }
        }
        .padding(layout.stickInset)
    }

    private func scheduleAutoReturn() {
        guard (MapTouchSettings.defaults.object(forKey: MapTouchSettings.autoReturnKey) as? Bool) ?? true else { return }
        autoReturnTask?.cancel()
        autoReturnTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled, !camera.following, let position = noahPosition else { return }
            withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.4)) {
                camera.recenter(on: position)
            }
        }
    }

    private var zoomControls: some View {
        VStack(spacing: 6) {
            if camera.zoom < MapTouchSettings.zoomPlan().levels.count - 1 {
                Button { camera.setZoom(camera.zoom + 1); store.logPlay(kind: "zoom", fields: ["level": "\(camera.zoom)", "source": "button", "zone": "bottom"]) } label: { Text(verbatim: "+") }
                    .buttonStyle(.ink(.secondary, fill: false))
            }
            if camera.zoom > 0 {
                Button { camera.setZoom(camera.zoom - 1); store.logPlay(kind: "zoom", fields: ["level": "\(camera.zoom)", "source": "button", "zone": "bottom"]) } label: { Text(verbatim: "−") }
                    .buttonStyle(.ink(.secondary, fill: false))
            }
        }
        .frame(width: 44)
        .padding(12)
    }

    /// 残骸のパネル(段階つきの資料など)。読める行と ■ の行、読める割合。閉じるまで地図は動いたまま。
    @ViewBuilder private var forgePanel: some View {
        if let page = store.panel {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(verbatim: page.title).font(InkFont.heading)
                    Spacer()
                    Button { store.closePanel() } label: { Text("閉じる") }
                        .buttonStyle(.ink(.quiet, fill: false))
                        .accessibilityIdentifier("panelClose")
                }
                if let r = page.readablePermille {
                    Text("読める割合 \(r / 10)%")
                    .font(InkFont.small)
                    .foregroundStyle(InkColor.textDim)
                }
                ScrollView {
                    Text(verbatim: page.body)
                        .font(.custom(FontBook.mapFont, size: 14))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 260)
            }
            .foregroundStyle(InkColor.text)
            .padding(InkMetric.gutter)
            .background(InkColor.panel.opacity(0.96))
            .overlay(alignment: .top) { Rectangle().fill(InkColor.accent).frame(height: 2) }
            .accessibilityIdentifier("forgePanel")
        }
    }

    /// 置くモードの帯(照準の上をもう一度タップしても建つ)。
    @ViewBuilder private var placingBar: some View {
        if store.placing != nil {
            HStack(spacing: InkMetric.gap) {
                if let r = store.preview?.reason {
                    Text(verbatim: r).font(InkFont.small).foregroundStyle(InkColor.alert).lineLimit(1)
                } else {
                    Text("置く場所をタップ").font(InkFont.small).foregroundStyle(InkColor.textDim)
                }
                Spacer(minLength: 4)
                if store.preview?.placeable == true {
                    Button { store.confirmPlacing() } label: { Text("ここに建てる") }
                        .buttonStyle(.ink(.primary, fill: false))
                        .accessibilityIdentifier("placeConfirm")
                }
                Button { store.cancelPlacing() } label: { Text("やめる") }
                    .buttonStyle(.ink(.quiet, fill: false))
            }
            .padding(8)
            .background(InkColor.panel.opacity(0.92))
        }
    }

    /// 地図の上のふきだし(調べた結果・流れている場面の行)。全画面の読み物にしない。
    @ViewBuilder private var bubbles: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !store.sceneLines.isEmpty {
                Bubble {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(store.sceneLines.enumerated()), id: \.offset) { _, line in
                            Text(verbatim: line)
                        }
                    }
                }
            }
            if let i = store.inspection {
                Bubble {
                    InspectionText(inspection: i)
                }
                .onTapGesture { store.dismissInspection() }
                .accessibilityIdentifier("inspection")
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .allowsHitTesting(store.inspection != nil)
    }
}

/// 黒地に細い枠のふきだし。
struct Bubble<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .font(InkFont.body)
            .foregroundStyle(InkColor.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: InkMetric.corner).fill(InkColor.panel.opacity(0.94)))
            .overlay(RoundedRectangle(cornerRadius: InkMetric.corner).stroke(InkColor.rule, lineWidth: InkMetric.rule))
    }
}

/// 調べた結果の行。数の言い回しは画面の固定文言(補間しないリテラル)と数を並べて組む。
struct InspectionText: View {
    let inspection: TileInspection

    static let tenths = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: inspection.title).bold()
            ForEach(Array(inspection.lines.enumerated()), id: \.offset) { _, line in
                switch line {
                case .name(let s):
                    Text(verbatim: s)
                case .remaining(let n):
                    HStack(spacing: 0) {
                        Text("残り")
                        Text(verbatim: " \(n) ")
                        Text("回")
                    }
                case .purityTenths(let n):
                    HStack(spacing: 0) {
                        Text("手ざわり: ")
                        Text(verbatim: Self.tenths[min(max(n, 1), 10) - 1])
                        Text("割くらい")
                    }
                }
            }
        }
    }
}
