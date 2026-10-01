import RFKernel
import Foundation

/// マスの見え方(原作 `TileVisibility`)。
public enum TileVisibility: UInt8, Codable, CaseIterable, Equatable, Sendable {
    /// 未踏(黒)
    case unseen
    /// 既知(前に見た。暗い地形だけ)
    case explored
    /// 視界の中(物と生き物も見える)
    case visible
}

/// 視界の半径の決まり(原作 `VisibilityLayer` の 昼 8・夜 −3・松明 +4・最小 2)。
public struct VisionRule: Codable, Equatable, Sendable {
    public var baseRadius: Int
    public var nightPenalty: Int
    public var torchBonus: Int
    public var minimumRadius: Int

    public init(baseRadius: Int = 8, nightPenalty: Int = -3, torchBonus: Int = 4, minimumRadius: Int = 2) {
        self.baseRadius = baseRadius
        self.nightPenalty = nightPenalty
        self.torchBonus = torchBonus
        self.minimumRadius = minimumRadius
    }

    public static let original = VisionRule()

    public func radius(isNight: Bool, hasTorch: Bool) -> Int {
        var r = baseRadius
        if isNight { r += nightPenalty }
        if hasTorch { r += torchBonus }
        return max(minimumRadius, r)
    }

    // 視界の円の判定はここ 1 か所(地図の既知・仲間の既知・画面の明暗はすべてこれを呼ぶ)。

    /// 中心から (dx, dy) ずれたマスが半径 r の円の中か(縁を含む。整数だけで判定)。
    public static func inCircle(dx: Int, dy: Int, radius r: Int) -> Bool {
        r >= 0 && dx * dx + dy * dy <= r * r
    }

    /// p が center を中心とする半径 r の円の中か。
    public static func inCircle(_ p: GridPoint, center: GridPoint, radius r: Int) -> Bool {
        inCircle(dx: p.x - center.x, dy: p.y - center.y, radius: r)
    }

    /// 円の中のマス(地図の外は除く。並びは行 → 列)。
    public static func cells(center: GridPoint, radius r: Int, in size: GridSize) -> [GridPoint] {
        guard r >= 0 else { return [] }
        var out: [GridPoint] = []
        for dy in -r...r {
            for dx in -r...r where inCircle(dx: dx, dy: dy, radius: r) {
                let p = GridPoint(center.x + dx, center.y + dy)
                if size.contains(p) { out.append(p) }
            }
        }
        return out
    }
}

/// 視界レイヤー(原作 `VisibilityLayer`)。いまの視界(中心と半径の円)と、見たことのあるマス(永続)を持つ。
/// 見たことのあるマスは 64×64 のチャンクごとのビット表で、必要なチャンクだけを作る(大きい地図でも軽い)。
public struct VisibilityLayer: Codable, Equatable, Sendable {
    public static let chunkSize = 64

    struct ChunkKey: Hashable, Comparable, Codable, Sendable {
        var cx: Int
        var cy: Int
        static func < (a: ChunkKey, b: ChunkKey) -> Bool { (a.cy, a.cx) < (b.cy, b.cx) }
    }

    public let size: MapSize
    /// チャンク → 64 行 × 64 bit。
    private var explored: [ChunkKey: [UInt64]] = [:]
    /// いまの視界の中心。まだ一度も見ていなければ nil。
    public private(set) var viewCenter: GridPoint?
    /// いまの視界の半径。
    public private(set) var viewRadius: Int = 0

    public init(size: MapSize) {
        self.size = size
    }

    /// 視界を動かす。円の中(地図の内側)を既知に記録し、新しく既知になったマスの数を返す。
    @discardableResult
    public mutating func update(center: GridPoint, radius: Int) -> Int {
        viewCenter = center
        viewRadius = max(0, radius)
        var added = 0
        for p in VisionRule.cells(center: center, radius: viewRadius, in: size) where setExplored(p) {
            added += 1
        }
        return added
    }

    /// 視界を消す(画面を離れたときなど)。既知はそのまま。
    public mutating func clearView() {
        viewCenter = nil
        viewRadius = 0
    }

    /// 長方形(両端を含む)を既知にする(拠点の初期の既知など)。
    public mutating func markExplored(from lo: GridPoint, to hi: GridPoint) {
        for y in max(0, lo.y)...min(size.height - 1, hi.y) {
            for x in max(0, lo.x)...min(size.width - 1, hi.x) {
                setExplored(GridPoint(x, y))
            }
        }
    }

    /// マスの見え方。地図の外は未踏。
    public func state(at p: GridPoint) -> TileVisibility {
        guard size.contains(p) else { return .unseen }
        if isInView(p) { return .visible }
        return isExplored(p) ? .explored : .unseen
    }

    /// いまの視界の中か。
    public func isInView(_ p: GridPoint) -> Bool {
        guard let c = viewCenter, size.contains(p) else { return false }
        return VisionRule.inCircle(p, center: c, radius: viewRadius)
    }

    /// 見たことがあるか(いま見えているマスも含む)。
    public func isKnown(_ p: GridPoint) -> Bool {
        state(at: p) != .unseen
    }

    /// 既知のマスの数。
    public var exploredCount: Int {
        explored.values.reduce(0) { $0 + $1.reduce(0) { $0 + $1.nonzeroBitCount } }
    }

    /// 既知のマスを列挙(行優先)。
    public var exploredCells: [GridPoint] {
        var out: [GridPoint] = []
        for key in explored.keys.sorted() {
            let rows = explored[key]!
            for ly in 0..<Self.chunkSize where rows[ly] != 0 {
                for lx in 0..<Self.chunkSize where rows[ly] & (1 << UInt64(lx)) != 0 {
                    out.append(GridPoint(key.cx * Self.chunkSize + lx, key.cy * Self.chunkSize + ly))
                }
            }
        }
        return out.sorted()
    }

    private func isExplored(_ p: GridPoint) -> Bool {
        let key = ChunkKey(cx: p.x / Self.chunkSize, cy: p.y / Self.chunkSize)
        guard let rows = explored[key] else { return false }
        return rows[p.y % Self.chunkSize] & (1 << UInt64(p.x % Self.chunkSize)) != 0
    }

    /// 既知にする。新しく既知になったら true。
    @discardableResult
    private mutating func setExplored(_ p: GridPoint) -> Bool {
        let key = ChunkKey(cx: p.x / Self.chunkSize, cy: p.y / Self.chunkSize)
        let bit: UInt64 = 1 << UInt64(p.x % Self.chunkSize)
        let row = p.y % Self.chunkSize
        if explored[key] == nil { explored[key] = [UInt64](repeating: 0, count: Self.chunkSize) }
        if explored[key]![row] & bit != 0 { return false }
        explored[key]![row] |= bit
        return true
    }

    // MARK: Codable(チャンクを座標順に並べ、ビット表は base64)

    private struct SavedChunk: Codable {
        var cx: Int
        var cy: Int
        var bits: Data
    }

    private enum CodingKeys: String, CodingKey { case size, chunks, viewCenter, viewRadius }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        size = try c.decode(MapSize.self, forKey: .size)
        viewCenter = try c.decodeIfPresent(GridPoint.self, forKey: .viewCenter)
        viewRadius = try c.decode(Int.self, forKey: .viewRadius)
        for ch in try c.decode([SavedChunk].self, forKey: .chunks) {
            guard ch.bits.count == Self.chunkSize * 8 else {
                throw DecodingError.dataCorruptedError(forKey: .chunks, in: c, debugDescription: "視界のチャンクの長さが合わない")
            }
            let bytes = [UInt8](ch.bits)
            var rows = [UInt64](repeating: 0, count: Self.chunkSize)
            for r in 0..<Self.chunkSize {
                var v: UInt64 = 0
                for b in 0..<8 { v |= UInt64(bytes[r * 8 + b]) << UInt64(b * 8) }
                rows[r] = v
            }
            explored[ChunkKey(cx: ch.cx, cy: ch.cy)] = rows
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(size, forKey: .size)
        try c.encodeIfPresent(viewCenter, forKey: .viewCenter)
        try c.encode(viewRadius, forKey: .viewRadius)
        let chunks = explored.keys.sorted().map { key -> SavedChunk in
            var bytes = [UInt8](); bytes.reserveCapacity(Self.chunkSize * 8)
            for v in explored[key]! { for b in 0..<8 { bytes.append(UInt8(truncatingIfNeeded: v >> UInt64(b * 8))) } }
            return SavedChunk(cx: key.cx, cy: key.cy, bits: Data(bytes))
        }
        try c.encode(chunks, forKey: .chunks)
    }
}
