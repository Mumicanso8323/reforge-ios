import Foundation
import RFKernel

/// 地図の上の連続の座標(マス単位。マス (x, y) の中心は (x + 0.5, y + 0.5))。
public struct MapPointF: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public init(cellCenter p: GridPoint) { self.init(x: Double(p.x) + 0.5, y: Double(p.y) + 0.5) }
}

/// 画面の上の点・大きさ(pt)。SwiftUI の CGPoint/CGSize の代わり(Linux でテストできるように)。
public struct ScreenPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct ScreenSize: Equatable, Sendable {
    public var width: Double
    public var height: Double
    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

/// 地図の視点(order.md §5.5 の操作)。画面側の状態で、本体の世界状態には入れない。
///
/// - 拡大・縮小はピンチで 3 段にスナップ(1 マス 18 / 24 / 32pt)。中間の倍率は使わない。
/// - 1 本指のドラッグで見回すと追従が外れる(画面は右下に「◎」を出し、押すとノアに戻る)。
/// - 追従している間は、補間したノアの位置を中心にする。
public struct MapCamera: Equatable, Sendable {
    public static let cellSizes: [Double] = [18, 24, 32]
    public static let defaultZoom = 1

    public var zoom: Int
    /// 画面の中心に来る地図の座標。
    public var center: MapPointF
    public var following: Bool

    public init(center: MapPointF = MapPointF(x: 0, y: 0), zoom: Int = MapCamera.defaultZoom, following: Bool = true) {
        self.center = center
        self.zoom = min(max(zoom, 0), Self.cellSizes.count - 1)
        self.following = following
    }

    /// 1 マスの一辺(pt)。
    public var cellSize: Double { Self.cellSizes[zoom] }

    /// ピンチの倍率(始めた段 × scale)に一番近い段(倍率は対数で比べる)。
    public static func snappedZoom(from start: Int, pinchScale: Double) -> Int {
        let s = min(max(start, 0), cellSizes.count - 1)
        guard pinchScale.isFinite, pinchScale > 0 else { return s }
        let target = log(cellSizes[s] * pinchScale)
        var best = s
        var bestD = Double.infinity
        for (i, c) in cellSizes.enumerated() {
            let d = abs(log(c) - target)
            if d < bestD { best = i; bestD = d }
        }
        return best
    }

    /// 画面の点 → マス(タップ・長押しの的)。
    public func cell(at p: ScreenPoint, in view: ScreenSize) -> GridPoint {
        let mx = center.x + (p.x - view.width / 2) / cellSize
        let my = center.y + (p.y - view.height / 2) / cellSize
        return GridPoint(Int(mx.rounded(.down)), Int(my.rounded(.down)))
    }

    /// 地図の座標 → 画面の点。
    public func screen(_ m: MapPointF, in view: ScreenSize) -> ScreenPoint {
        ScreenPoint(x: (m.x - center.x) * cellSize + view.width / 2, y: (m.y - center.y) * cellSize + view.height / 2)
    }

    /// マスの左上の画面の点。
    public func screenOrigin(of c: GridPoint, in view: ScreenSize) -> ScreenPoint {
        screen(MapPointF(x: Double(c.x), y: Double(c.y)), in: view)
    }

    /// 画面に映るマスの範囲(端の 1 マスを含む)。
    public func visibleCells(in view: ScreenSize) -> GridRect {
        let a = cell(at: ScreenPoint(x: 0, y: 0), in: view)
        let b = cell(at: ScreenPoint(x: view.width, y: view.height), in: view)
        return GridRect(origin: a, size: GridSize(width: b.x - a.x + 1, height: b.y - a.y + 1))
    }

    /// 1 本指のドラッグ(指が動いた分だけ地図が動く)。追従を外す。
    public mutating func pan(byScreen dx: Double, _ dy: Double, mapSize: GridSize) {
        center.x -= dx / cellSize
        center.y -= dy / cellSize
        following = false
        clamp(to: mapSize)
    }

    /// 追従中なら中心を合わせる(毎フレーム)。
    public mutating func follow(_ m: MapPointF) {
        if following { center = m }
    }

    /// 「◎」: ノアに戻って追従を再開する。
    public mutating func recenter(on m: MapPointF) {
        center = m
        following = true
    }

    /// 段を変える(画面の中心はそのまま)。
    public mutating func setZoom(_ z: Int) {
        zoom = min(max(z, 0), Self.cellSizes.count - 1)
    }

    /// 見回しで地図の外へ行き過ぎない(中心は地図の中)。
    public mutating func clamp(to size: GridSize) {
        center.x = min(max(center.x, 0), Double(size.width))
        center.y = min(max(center.y, 0), Double(size.height))
    }
}

extension ActorSprite {
    /// 歩く速さ(原作 MapScreen.cs の MoveAnimInterval 0.25 秒 = 1 秒 4 マス)。
    public static let walkTilesPerSecond = 4.0

    /// 先へ延ばす時間の上限(秒)。ステップ(約 10 回/秒)の 1 つ分と少し。Frame が遅れても(本体が重い・止まっている)、
    /// 来ていない歩みの先まで絵を進めない(進んでから戻って見える食い違いを出さない)。
    public static let maxExtrapolationSeconds = 0.12

    /// 補間した位置(マス単位の連続の座標。マスの中心)。
    /// Frame を受け取ってから elapsed 秒たったときの位置: 進み(千分率)を歩く速さで先に進め、次のマスで止める。
    /// シミュレーションのステップ(約 10 回/秒)ごとに Frame が来るので、その間を 60fps で埋める。
    public func position(elapsed: Double) -> MapPointF {
        let a = MapPointF(cellCenter: from)
        guard from != to else { return a }
        let b = MapPointF(cellCenter: to)
        let ahead = min(max(0, elapsed), Self.maxExtrapolationSeconds) * Self.walkTilesPerSecond * 1000
        let t = min(1, max(0, (Double(progress) + ahead) / 1000))
        return MapPointF(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    /// 歩いているか(描画を止めてよいかの判定)。
    public var isMoving: Bool { from != to }
}
