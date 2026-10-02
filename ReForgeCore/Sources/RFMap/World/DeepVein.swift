import RFKernel

/// 岩山の奥の鉱脈の目印の規則(U19)。地図の設定 deepVein があれば、岩山の岩場のうち拠点からいちばん遠いマスに
/// 1 つ必ず置く(ほかの鉱脈から 2 マス以上離す)。硬さ(掘るのに要る刃の段)はコンテンツの mining で決める。
/// 乱数は seed から別に引く(SeededRandom.derived(seed, 103))。無ければ何も置かず、乱数も引かない。
public struct DeepVeinRule: Codable, Equatable, Sendable {
    /// 鉱脈の種類(既定 rare)。
    public var category: DepositCategory?

    public init(category: DepositCategory? = nil) {
        self.category = category
    }
}

extension TypedID where Tag == DepositTag {
    /// 岩山の奥の鉱脈。
    public static let deepVein = DepositID("deposit.mountain.deep")
}

enum DeepVein {
    /// 置いた位置(置けなければ nil)。
    @discardableResult
    static func place(_ rule: DeepVeinRule, in layer: inout MapLayer, landmarks lm: Landmarks, seed: UInt64) -> GridPoint? {
        let r = lm.mountainRadius + 1
        let origin = lm.base.center
        var best: (d: Int, p: GridPoint)?
        for y in (lm.mountainCenter.y - r)...(lm.mountainCenter.y + r) {
            for x in (lm.mountainCenter.x - r)...(lm.mountainCenter.x + r) {
                let p = GridPoint(x, y)
                guard layer.size.contains(p), layer.terrain.biome(at: p) == .rock else { continue }
                if layer.deposits.all.contains(where: { $0.position.chebyshev(to: p) < 2 }) { continue }
                let dx = p.x - origin.x, dy = p.y - origin.y
                let d = dx * dx + dy * dy
                if best.map({ d > $0.d || (d == $0.d && p < $0.p) }) ?? true { best = (d, p) }
            }
        }
        guard let at = best?.p else { return nil }
        var rng = SeededRandom.derived(from: seed, 103)
        layer.deposits.add(DepositGenerator.make(id: .deepVein, at: at, category: rule.category ?? .rare, rng: &rng))
        return at
    }
}
