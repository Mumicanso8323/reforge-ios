import Foundation
import RFContent
import RFKernel

/// 品の名前の色(原作 visual-design.md §2〜§3 の移植)。
/// 色の系統(ItemTint)は認識の層の見え方から来る。ここは真実の素材を一切見ない。
/// - 明度 = 純度(見えていないときは中くらい)
/// - 彩度 = 鮮やかさの段
/// - 色相 = 系統
public enum ItemColor {
    /// 名前の文字に付く動き。
    public struct Effects: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        /// 光沢が横切る(上質以上の金属系)。
        public static let gloss = Effects(rawValue: 1 << 0)
        /// ゆっくり明滅する(希少以上)。
        public static let pulse = Effects(rawValue: 1 << 1)
        /// 色相がゆらぐ(紫の最上段だけ)。
        public static let shimmer = Effects(rawValue: 1 << 2)
        /// 一瞬白く光る(宝石)。
        public static let sparkle = Effects(rawValue: 1 << 3)
    }

    /// 鮮やかさの段ごとの彩度(原作の彩度テーブル)。
    static let saturation: [Double] = [0.1, 0.25, 0.4, 0.6, 0.75, 0.85]

    /// 系統の色相(度)。
    static func hueDegrees(_ h: ItemTint.Hue) -> Double {
        switch h {
        case .neutral: 0
        case .warm: 30
        case .green: 90
        case .blue: 200
        case .violet: 280
        }
    }

    /// 地の色(動きを付ける前)。purity が nil なら純度は見えていない(中くらいの明るさ)。
    public static func base(_ tint: ItemTint, purity: Purity?) -> RGB {
        let value: Double
        if let p = purity {
            let pct = Double(p.basisPoints) / 100
            var v = 0.3 + 0.6 * min(1, max(0, (pct - 20) / 80))
            if p.basisPoints >= 9900 {
                let nines = p.basisPoints >= 10000 ? 6 : log10(10000.0 / Double(10000 - p.basisPoints))
                v = min(1, v + 0.1 * nines)
            }
            value = v
        } else {
            value = 0.6
        }
        let sat = tint.hue == .neutral ? 0.04 : saturation[max(0, min(5, tint.vividness))]
        return hsv(hueDegrees(tint.hue), sat, value)
    }

    /// 付ける動き(原作のエフェクト適用テーブル)。
    public static func effects(_ tint: ItemTint, purity: Purity?) -> Effects {
        var e: Effects = []
        if tint.hue == .warm && tint.vividness >= 2 { e.insert(.gloss) }
        if tint.vividness >= 3 && tint.hue != .green { e.insert(.pulse) }
        if tint.hue == .violet && tint.vividness >= 5 { e.insert(.shimmer) }
        if tint.sparkle == true { e.insert(.sparkle) }
        return e
    }

    /// 動きを付けた 1 文字の色。index は名前の中の文字の位置、time は秒。
    public static func animated(_ base: RGB, effects: Effects, index: Int, length: Int, time: Double, seed: Int = 0) -> RGB {
        var c = base
        if effects.contains(.shimmer) {
            let h = 280 + 25 * sin(time * 1.5)
            let s = 0.7 + 0.15 * sin(time * 2.3)
            let v = 0.7 + 0.15 * sin(time * 0.8)
            c = hsv(h, s, v)
        }
        if effects.contains(.pulse) {
            let pulse = sin(time * 0.5 * .pi * 2) * 0.5 + 0.5
            c = lift(c, Int(pulse * 30))
        }
        if effects.contains(.gloss) {
            let cycle = time.truncatingRemainder(dividingBy: 4)
            if cycle <= 0.3 {
                let pos = (cycle / 0.3) * Double(length + 4) - 2
                let glow = max(0, 1 - abs(Double(index) - pos) * 0.5)
                c = lift(c, Int(glow * 80))
            }
        }
        if effects.contains(.sparkle) {
            let phase = sin(time * 0.3 + Double(seed) * 1.7) * sin(time * 0.7 + Double(seed) * 2.3)
            if phase > 0.92 { c = lift(c, Int((phase - 0.92) / 0.08 * 120)) }
        }
        return c
    }

    static func lift(_ c: RGB, _ k: Int) -> RGB {
        func f(_ v: UInt8) -> UInt8 { UInt8(min(255, Int(v) + k)) }
        return RGB(f(c.r), f(c.g), f(c.b))
    }

    static func hsv(_ h: Double, _ s: Double, _ v: Double) -> RGB {
        let hh = (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let i = Int(hh)
        let f = hh - Double(i)
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        let (r, g, b): (Double, Double, Double)
        switch i {
        case 0: (r, g, b) = (v, t, p)
        case 1: (r, g, b) = (q, v, p)
        case 2: (r, g, b) = (p, v, t)
        case 3: (r, g, b) = (p, q, v)
        case 4: (r, g, b) = (t, p, v)
        default: (r, g, b) = (v, p, q)
        }
        func b8(_ x: Double) -> UInt8 { UInt8(max(0, min(255, (x * 255).rounded()))) }
        return RGB(b8(r), b8(g), b8(b))
    }
}
