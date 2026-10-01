import SwiftUI
import ReForgeEngine

/// 主画面の地図(order.md §5.5)。
///
/// | 操作 | 指 | 結果 |
/// | 歩く | マスをタップ | 経路を点線で描き、すぐ歩き出す(確認なし)。歩いている間の別のタップで行き先が変わる |
/// | 見回す | 1 本指のドラッグ | 視点だけ動く。追従が外れ、右下に「◎」(押すとノアに戻る) |
/// | 拡大・縮小 | ピンチ | 3 段にスナップ(1 マス 18 / 24 / 32pt)。中間の倍率は使わない |
/// | 調べる | 長押し | ふきだしで名前・鉱脈の見た目・残り回数・ノアの手ざわり |
///
/// タップ・長押し・ドラッグは 1 つの DragGesture(最小距離 0)で見分ける(長押しは押している間に 0.5 秒で出す)。
struct MapCanvasView: View {
    let store: GameStore
    @State private var camera = MapCamera()
    @State private var touch: Touch?
    @State private var pinchStartZoom: Int?
    @State private var longPressTask: Task<Void, Never>?

    private struct Touch {
        var start: CGPoint
        var last: CGPoint
        var panned = false
        var longPressed = false
        var pinching = false
    }

    static let panThreshold: CGFloat = 10
    static let longPressNanoseconds: UInt64 = 500_000_000

    var body: some View {
        GeometryReader { geo in
            let view = ScreenSize(width: Double(geo.size.width), height: Double(geo.size.height))
            // 動く物が無い間は毎フレーム描かない(Frame が来たときだけ描き直す)。
            TimelineView(.animation(minimumInterval: nil, paused: !store.actors.contains(where: \.isMoving))) { _ in
                let scene = currentScene()
                Canvas(opaque: true, rendersAsynchronously: false) { ctx, size in
                    scene.draw(&ctx, size: size)
                }
            }
            .contentShape(Rectangle())
            .gesture(drag(view))
            .simultaneousGesture(pinch)
            .overlay(alignment: .bottomTrailing) { recenterButton }
            .overlay(alignment: .top) { bubbles }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("map")
        }
        .background(Color.black)
        .clipped()
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

    private func currentScene() -> MapScene {
        MapScene(camera: liveCamera(), map: store.mapView, chunks: store.chunks, actors: store.actors,
                 placements: store.placements, route: store.route, night: store.clock.isNight, elapsed: elapsed,
                 terrains: store.content.terrains)
    }

    // MARK: - 指

    private func drag(_ view: ScreenSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { v in
                if touch == nil {
                    touch = Touch(start: v.startLocation, last: v.startLocation)
                    scheduleLongPress(at: v.startLocation, view: view)
                }
                guard var t = touch, !t.pinching, !t.longPressed else { return }
                let moved = hypot(v.location.x - t.start.x, v.location.y - t.start.y)
                if !t.panned, moved > Self.panThreshold {
                    t.panned = true
                    longPressTask?.cancel()
                    // 追従を外す: いま見えている中心から見回しを始める
                    camera.center = liveCamera().center
                    camera.following = false
                }
                if t.panned {
                    camera.pan(byScreen: Double(v.location.x - t.last.x), Double(v.location.y - t.last.y),
                               mapSize: store.mapView.size)
                    t.last = v.location
                }
                touch = t
            }
            .onEnded { v in
                longPressTask?.cancel()
                defer { touch = nil }
                guard let t = touch, !t.panned, !t.longPressed, !t.pinching else { return }
                store.walk(to: liveCamera().cell(at: ScreenPoint(x: Double(v.location.x), y: Double(v.location.y)), in: view))
            }
    }

    private func scheduleLongPress(at p: CGPoint, view: ScreenSize) {
        longPressTask?.cancel()
        longPressTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.longPressNanoseconds)
            guard !Task.isCancelled, var t = touch, !t.panned, !t.pinching else { return }
            t.longPressed = true
            touch = t
            store.inspect(liveCamera().cell(at: ScreenPoint(x: Double(p.x), y: Double(p.y)), in: view))
        }
    }

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { v in
                if pinchStartZoom == nil {
                    pinchStartZoom = camera.zoom
                    longPressTask?.cancel()
                }
                if var t = touch {
                    t.pinching = true
                    touch = t
                }
                let z = MapCamera.snappedZoom(from: pinchStartZoom ?? camera.zoom, pinchScale: Double(v.magnification))
                if z != camera.zoom { camera.setZoom(z) }
            }
            .onEnded { _ in pinchStartZoom = nil }
    }

    // MARK: - 重ねるもの

    @ViewBuilder private var recenterButton: some View {
        if !camera.following {
            Button {
                if let n = noahPosition { camera.recenter(on: n) } else { camera.following = true }
            } label: {
                Text(verbatim: "◎")
                    .font(.custom(FontBook.mapFont, fixedSize: 28))
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
            .font(.custom(FontBook.mapFont, size: 15))
            .foregroundStyle(Color(white: 0.92))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.08).opacity(0.92)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(white: 0.5), lineWidth: 1))
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
