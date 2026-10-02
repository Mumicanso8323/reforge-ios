import RFKernel
import RFMatter

/// 素材に触れると純度のおおよそが分かる。
/// R1 には純度を測る道具が無いので、試作の結果カードの純度・設計画面の入力の行・見込みは、この見当で出す。
///
/// - 見当は真の純度を刻み(既定 5%)の倍数に丸めたもの(四捨五入)。世界状態には真の純度だけを持ち、見当は表示のたびに出す。
/// - 他の人の見当と比べられる形は置かない(R1 にノアと他の 4 人を数値で比べる画面を作らない。結合設計 REQ-S5)。
public enum HandSense {
    /// 見当の刻み(万分率)。
    public static let resolution = 500

    public static func estimate(_ p: Purity, resolution: Int = resolution) -> Purity {
        guard resolution > 1 else { return p }
        let r = (p.basisPoints + resolution / 2) / resolution * resolution
        return Purity(basisPoints: r)
    }

    public static func estimate(_ m: Matter, resolution: Int = resolution) -> Purity {
        estimate(m.purity, resolution: resolution)
    }
}
