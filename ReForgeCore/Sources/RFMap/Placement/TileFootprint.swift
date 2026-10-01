/// 任意形状のマスの占有(原作 `TileFootprint`)。アンカーからの相対座標の集合。
/// L 字・T 字など長方形でない形も持てる。
public struct TileFootprint: Codable, Equatable, Hashable, Sendable {
    /// 占有するマスの相対座標(行優先で並べ、重複なし)。
    public let offsets: [GridPoint]
    public let width: Int
    public let height: Int

    public init(offsets: [GridPoint]) {
        let unique = Array(Set(offsets)).sorted()
        let cells = unique.isEmpty ? [GridPoint(0, 0)] : unique
        self.offsets = cells
        self.width = (cells.map(\.x).max() ?? 0) + 1
        self.height = (cells.map(\.y).max() ?? 0) + 1
    }

    /// 1 マス。
    public static let single = TileFootprint(offsets: [GridPoint(0, 0)])

    /// 幅 w × 高さ h の長方形。
    public static func rect(width w: Int, height h: Int) -> TileFootprint {
        var o: [GridPoint] = []
        for y in 0..<max(1, h) { for x in 0..<max(1, w) { o.append(GridPoint(x, y)) } }
        return TileFootprint(offsets: o)
    }

    /// 形の文字列から作る。`#` が占有、それ以外(`.` や空白)は空き。行は改行で区切る。
    public init(mask: String) {
        var o: [GridPoint] = []
        for (row, line) in mask.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            for (col, ch) in line.enumerated() where ch == "#" { o.append(GridPoint(col, row)) }
        }
        self.init(offsets: o)
    }

    /// 原作の TileLabel(改行区切りの文字列)から作る。全角スペース(U+3000)は空き、それ以外の文字は占有。
    public init(tileLabel: String) {
        guard !tileLabel.isEmpty else { self.init(offsets: [GridPoint(0, 0)]); return }
        var o: [GridPoint] = []
        for (row, line) in tileLabel.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            for (col, ch) in line.enumerated() where ch != "\u{3000}" { o.append(GridPoint(col, row)) }
        }
        self.init(offsets: o)
    }

    /// アンカーに置いたときに占めるマス。
    public func cells(at anchor: GridPoint) -> [GridPoint] {
        offsets.map { anchor + $0 }
    }

    public func occupies(_ offset: GridPoint) -> Bool { offsets.contains(offset) }
}
