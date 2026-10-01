import RFKernel
import Foundation

// Purity(万分率の整数)は RFKernel に移した(形・意味は同じ)。

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
