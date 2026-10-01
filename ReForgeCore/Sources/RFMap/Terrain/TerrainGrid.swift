import RFKernel
import Foundation

/// 層の地形。小さい地図(R1 の 96×96 など)は全マスを密に持ち、
/// 大きい地図(原作の 10000×10000)は BiomeField を必要なときに計算して、書き込んだマスだけを持つ。
public struct TerrainGrid: Codable, Equatable, Sendable {
    public let size: MapSize
    public let field: BiomeField
    /// 密に持つときの全マス(行優先、Biome の rawValue)。nil なら手続き的に求める。
    private var dense: [UInt8]?
    /// 手続き的なときに書き込んだマス(通し番号 → 地形)。
    private var overrides: [Int: Biome]

    /// - Parameter denseCellLimit: これ以下のマス数なら密に持つ。
    public init(field: BiomeField, denseCellLimit: Int) {
        self.size = field.size
        self.field = field
        self.overrides = [:]
        if field.size.cellCount <= denseCellLimit {
            var cells = [UInt8](repeating: 0, count: field.size.cellCount)
            for y in 0..<size.height {
                for x in 0..<size.width {
                    cells[y * size.width + x] = field.naturalBiome(at: GridPoint(x, y)).rawValue
                }
            }
            dense = cells
        } else {
            dense = nil
        }
    }

    /// 全マスを手で与える(試験用の地図・地下の層など)。下地の場は seed 0 のもの(地形の判定には使わない)。
    public init(size: MapSize, cells: [Biome]) {
        precondition(cells.count == size.count, "cells は size.count 個")
        self.size = size
        self.field = BiomeField(seed: 0, size: size)
        self.overrides = [:]
        self.dense = cells.map(\.rawValue)
    }

    /// 全マスを密に持っているか。
    public var isDense: Bool { dense != nil }

    /// マスの地形。地図の外は nil。
    @inlinable
    public func biome(at p: GridPoint) -> Biome? {
        guard size.contains(p) else { return nil }
        return biomeUnchecked(size.index(p), p)
    }

    @usableFromInline
    func biomeUnchecked(_ index: Int, _ p: GridPoint) -> Biome {
        if let dense { return Biome(rawValue: dense[index]) ?? .plain }
        if let o = overrides[index] { return o }
        return field.naturalBiome(at: p)
    }

    /// マスの地形を書き換える(生成時の川・森・岩山・拠点の書き込み用)。地図の外は無視する。
    public mutating func set(_ p: GridPoint, _ biome: Biome) {
        guard size.contains(p) else { return }
        let i = size.index(p)
        if dense != nil {
            dense![i] = biome.rawValue
        } else {
            overrides[i] = biome
        }
    }

    /// 範囲内のマスを数える(検査用)。
    public func count(_ biome: Biome, in rect: (min: GridPoint, max: GridPoint)? = nil) -> Int {
        let lo = rect?.min ?? GridPoint(0, 0)
        let hi = rect?.max ?? GridPoint(size.width - 1, size.height - 1)
        var n = 0
        for y in max(0, lo.y)...min(size.height - 1, hi.y) {
            for x in max(0, lo.x)...min(size.width - 1, hi.x) where self.biome(at: GridPoint(x, y)) == biome {
                n += 1
            }
        }
        return n
    }

    // MARK: Codable(密な地形は base64 の 1 本の文字列にして小さく保つ)

    private enum CodingKeys: String, CodingKey { case field, dense, overrides }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        field = try c.decode(BiomeField.self, forKey: .field)
        size = field.size
        // base64 の文字列で読み書きする(Data の Codable はエンコーダ次第で配列にもなるため。保存の正準 JSON と揃える)
        if let text = try c.decodeIfPresent(String.self, forKey: .dense) {
            guard let data = Data(base64Encoded: text), data.count == size.cellCount else {
                throw DecodingError.dataCorruptedError(forKey: .dense, in: c, debugDescription: "地形のマス数が合わない")
            }
            dense = [UInt8](data)
        } else {
            dense = nil
        }
        let pairs = try c.decodeIfPresent([[Int]].self, forKey: .overrides) ?? []
        var o: [Int: Biome] = [:]
        for pair in pairs where pair.count == 2 {
            guard let b = Biome(rawValue: UInt8(clamping: pair[1])) else { continue }
            o[pair[0]] = b
        }
        overrides = o
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(field, forKey: .field)
        if let dense {
            try c.encode(Data(dense).base64EncodedString(), forKey: .dense)
        } else {
            let pairs = overrides.keys.sorted().map { [$0, Int(overrides[$0]!.rawValue)] }
            try c.encode(pairs, forKey: .overrides)
        }
    }
}
