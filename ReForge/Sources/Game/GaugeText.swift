import ReForgeEngine

/// 数値の棒を文字で描く(■ 満ち・□ 空き・目盛りのマスは ┃)。目盛りの意味は書かない。担当: U18。
enum GaugeText {
    static func render(_ g: StatGauge, width: Int) -> String {
        let w = max(1, width)
        let filled = (g.fillPermille * w + 500) / 1000
        let markCells = Set(g.marks.map { min(w - 1, max(0, $0 * w / 1000)) })
        return String((0..<w).map { i in markCells.contains(i) ? "┃" : (i < filled ? "■" : "□") })
    }
}
