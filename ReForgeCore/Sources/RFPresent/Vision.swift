import RFKernel
import RFWorld

/// いま見えている範囲 1 つ(中心と半径の円。原作 VisibilityLayer と同じユークリッドの円: dx² + dy² ≤ r²)。
///
/// 仮の置き場: 視界の規則は地図の担当(U1)の RFMap に 1 か所で置き、人(RFCrew)の既知の書き込みと画面の両方が
/// それを呼ぶ形に統合のときに寄せる(統合担当と合意済み)。それまでは RFPresent の中で閉じる。
public struct VisionArea: Hashable, Sendable {
    public var center: GridPoint
    public var radius: Int

    public init(center: GridPoint, radius: Int) {
        self.center = center
        self.radius = radius
    }

    public func contains(_ p: GridPoint) -> Bool {
        let dx = p.x - center.x, dy = p.y - center.y
        return dx * dx + dy * dy <= radius * radius
    }

    /// 行ごとの横の範囲(y, 左端, 右端)。画面はこれで切り抜きの形を作る(マス単位のぎざぎざの円)。
    public var rowSpans: [(y: Int, minX: Int, maxX: Int)] {
        (-radius...max(-radius, radius)).map { dy in
            var half = 0
            while (half + 1) * (half + 1) + dy * dy <= radius * radius { half += 1 }
            return (center.y + dy, center.x - half, center.x + half)
        }
    }

    /// 囲む四角。
    public var bounds: GridRect {
        GridRect(origin: GridPoint(center.x - radius, center.y - radius),
                 size: GridSize(width: radius * 2 + 1, height: radius * 2 + 1))
    }
}

/// 視界の半径の決まり(原作 VisibilityLayer: 昼 8・夜 −3・灯り +4・最小 2)。仮置き(上の注記)。
public struct VisionRadiusRule: Equatable, Sendable {
    public var day = 8
    public var nightPenalty = -3
    public var lightBonus = 4
    public var minimum = 2

    public init() {}

    public func radius(phase: DayPhase, hasLight: Bool = false) -> Int {
        var r = day
        if phase != .day { r += nightPenalty }
        if hasLight { r += lightBonus }
        return max(minimum, r)
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
