import RFKernel
import Foundation

// Purity(万分率の整数)は RFKernel に移した(形・意味は同じ)。
// 保存の読み込みで範囲外を throw するのは、RFMatter 側では Matter の decode で確かめている。

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

/// R1 の鉱石の純度の範囲(order.md §5.6 を、レビューの決定で露頭だけ 20〜35% に広げた)。
/// 地図の生成側がこの範囲で鉱石を作る前提で、工程の規則と式は決めてある。
public enum R1Ore {
    /// 岩山の露頭(手で掘れる最初の鉱石)。この範囲で木炭炉 1 回が粗鉄塊(〜21%)と鉄塊の両方になる。
    public static let outcrop = Purity(percent: 20)...Purity(percent: 35)
    /// 鉱脈(採掘口を置く)。
    public static let deposit = Purity(percent: 35)...Purity(percent: 60)
}

/// 保存用の符号化。辞書(規則の表・特性)の並びが実行ごとに変わらないよう、キーを並べ替えて書く。
/// セーブ・規則の表の書き出しはこの encoder を使う前提。
public enum MatterCoding {
    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }
}
