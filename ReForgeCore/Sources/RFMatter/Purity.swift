import Foundation

/// 純度(または組成の割合)。万分率の整数で持つ(10000 = 100.00%)。
///
/// 原作は C# の `decimal`(10 進の固定小数)で計算していた。2 進の浮動小数だと 85.00% の境目が
/// 84.999…% に落ちて名前が揺れるので、整数の万分率で持ち、境目を厳密に比べる。
/// 設計担当の RFKernel に同じ型ができたら、そちらを正としてこの型を置き換える。
public struct Purity: Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
    /// 万分率(0...10000)。
    public let basisPoints: Int

    public static let zero = Purity(basisPoints: 0)
    public static let full = Purity(basisPoints: 10000)

    /// 範囲外は 0...10000 に丸める(原作 `Math.Clamp(outputPurity, 0, 100)`)。
    public init(basisPoints: Int) {
        self.basisPoints = min(max(basisPoints, 0), 10000)
    }

    /// 百分率で作る(例: `Purity(percent: 30)` = 30.00%)。
    public init(percent: Int, hundredths: Int = 0) {
        self.init(basisPoints: percent * 100 + hundredths)
    }

    /// 百分率(表示・テスト用。計算には使わない)。
    public var percent: Double { Double(basisPoints) / 100 }

    public static func < (a: Purity, b: Purity) -> Bool { a.basisPoints < b.basisPoints }

    public static func + (a: Purity, b: Purity) -> Purity { Purity(basisPoints: a.basisPoints + b.basisPoints) }

    public var description: String {
        String(format: "%d.%02d%%", basisPoints / 100, basisPoints % 100)
    }

    // Codable: 整数 1 つで保存する(セーブの互換を取りやすい)。
    public init(from decoder: Decoder) throws {
        self.init(basisPoints: try decoder.singleValueContainer().decode(Int.self))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(basisPoints)
    }
}

/// 純度の効き(原作 `NameGenerator.Nines` / `PurityEffect`、naming-engine.md のナイン方式)。
/// 表示と装備の性能用。工程の計算(純度・名前・硬さ)には使わない(対数は端末ごとに末位がずれうるので、
/// 決定的であるべき計算に混ぜない)。
public enum PurityMath {
    /// ナイン数 = log10(100 / (100 − 純度))。90% → 1、99% → 2、99.9% → 3。100% は 6 で頭打ち。
    public static func nines(_ p: Purity) -> Double {
        if p.basisPoints >= 10000 { return 6 }
        if p.basisPoints <= 0 { return 0 }
        return log10(10000.0 / Double(10000 - p.basisPoints))
    }

    /// 性能倍率 = 1 + α × ナイン数²(α 既定 0.1)。90% → ×1.10、99% → ×1.40。
    public static func effect(_ p: Purity, alpha: Double = 0.1) -> Double {
        let n = nines(p)
        return 1 + alpha * n * n
    }
}
