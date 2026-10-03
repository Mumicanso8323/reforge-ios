import RFContent
import RFKernel
import RFMap
import RFWorld

/// ノアが自分で歩ける範囲(操作棒と行き先の指定が同じ規則を引く)。保存の形には入らず、毎回の計算で決まる。
/// 夜と、最初の行為の前(時計の保留の間)は、燃えている火床の灯りの半径の中だけ。昼は、ノアのまわりの昼の視界の中。
public enum WalkRange {
    public struct Circle: Equatable, Sendable {
        public var center: GridPoint
        public var radius: Int

        public init(center: GridPoint, radius: Int) {
            self.center = center
            self.radius = radius
        }

        public func contains(_ p: GridPoint) -> Bool { VisionRule.inCircle(p, center: center, radius: radius) }
    }

    /// 灯りだけで歩く時間帯か。
    public static func isLightOnly(_ w: WorldState) -> Bool { w.clock.isNight || w.clock.held }

    /// 範囲を作る円(ノアのいる層)。灯りの時間帯に灯りが無ければ、ノアの夜の視界を代わりにする(動けなくならない)。
    public static func circles(_ w: WorldState, content: ContentDB, layer: LayerID) -> [Circle] {
        guard let noah = w.people[.noah]?.position, noah.layer == layer else { return [] }
        let rule = VisionRule.original
        if isLightOnly(w) {
            let lights = w.placements.sortedIDs.compactMap { id -> Circle? in
                guard let p = w.placements.items[id], p.at.layer == layer else { return nil }
                let r = Hearths.lightRadius(p, content)
                return r > 0 ? Circle(center: p.at.point, radius: r) : nil
            }
            if !lights.isEmpty { return lights }
            return [Circle(center: noah.point, radius: rule.radius(isNight: true, hasTorch: false))]
        }
        return [Circle(center: noah.point, radius: rule.radius(isNight: false, hasTorch: false))]
    }

    /// p がノアの歩ける範囲の中か。ノアの今いるマスは常に中。
    public static func contains(_ p: GridPoint, layer: LayerID, _ w: WorldState, content: ContentDB) -> Bool {
        if let noah = w.people[.noah]?.position, noah.layer == layer, noah.point == p { return true }
        return circles(w, content: content, layer: layer).contains { $0.contains(p) }
    }

    /// 行ごとの横の範囲(円の和。行の中の隙間は埋めない)。
    public static func rowSpans(_ circles: [Circle]) -> [(y: Int, minX: Int, maxX: Int)] {
        var rows: [Int: [ClosedRange<Int>]] = [:]
        for c in circles {
            for dy in -c.radius...c.radius {
                var half = 0
                while VisionRule.inCircle(dx: half + 1, dy: dy, radius: c.radius) { half += 1 }
                rows[c.center.y + dy, default: []].append((c.center.x - half)...(c.center.x + half))
            }
        }
        var out: [(y: Int, minX: Int, maxX: Int)] = []
        for y in rows.keys.sorted() {
            let sorted = rows[y]!.sorted { $0.lowerBound < $1.lowerBound }
            var cur = sorted[0]
            for r in sorted.dropFirst() {
                if r.lowerBound <= cur.upperBound + 1 { cur = cur.lowerBound...max(cur.upperBound, r.upperBound) } else {
                    out.append((y, cur.lowerBound, cur.upperBound))
                    cur = r
                }
            }
            out.append((y, cur.lowerBound, cur.upperBound))
        }
        return out
    }
}
