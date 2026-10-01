import RFKernel
import RFMap
import RFWorld

/// いま見えている範囲 1 つ(画面の切り抜き用の形)。円の判定と半径の決まりは RFMap の VisionRule が 1 か所で持つ
/// (人の既知の書き込み・地図の視界・画面の明暗が同じ規則を呼ぶ)。
public struct VisionArea: Hashable, Sendable {
    public var center: GridPoint
    public var radius: Int

    public init(center: GridPoint, radius: Int) {
        self.center = center
        self.radius = radius
    }

    public func contains(_ p: GridPoint) -> Bool { VisionRule.inCircle(p, center: center, radius: radius) }

    /// 行ごとの横の範囲(y, 左端, 右端)。画面はこれで切り抜きの形を作る(マス単位のぎざぎざの円)。
    public var rowSpans: [(y: Int, minX: Int, maxX: Int)] {
        (-radius...max(-radius, radius)).map { dy in
            var half = 0
            while VisionRule.inCircle(dx: half + 1, dy: dy, radius: radius) { half += 1 }
            return (center.y + dy, center.x - half, center.x + half)
        }
    }

    /// 囲む四角。
    public var bounds: GridRect {
        GridRect(origin: GridPoint(center.x - radius, center.y - radius),
                 size: GridSize(width: radius * 2 + 1, height: radius * 2 + 1))
    }
}

/// 視界の半径を世界の相から引く(数は RFMap の VisionRule: 昼 8・夜 −3・灯り +4・最小 2)。
public struct VisionRadiusRule: Equatable, Sendable {
    public var rule = VisionRule.original

    public init() {}

    public func radius(phase: DayPhase, hasLight: Bool = false) -> Int {
        rule.radius(isNight: phase != .day, hasTorch: hasLight)
    }

    /// 一員それぞれの視界(地表など、指定した層にいる人だけ)。
    public func areas(_ w: WorldState, layer: LayerID) -> [VisionArea] {
        let r = radius(phase: w.clock.phase)
        return w.people.members.compactMap { id in
            guard let pos = w.people[id]?.position, pos.layer == layer else { return nil }
            return VisionArea(center: pos.point, radius: r)
        }
    }
}
