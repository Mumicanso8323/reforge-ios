import RFKernel

/// 地図の生成の設定。
public struct MapGenerationConfig: Codable, Equatable, Sendable {
    public var size: MapSize
    public var landmarks: LandmarkRules
    /// バイオームの判定の閾値。
    public var biomes: BiomeThresholds
    /// これ以下のマス数なら地形を全マス密に持ち、生成時に全チャンクの POI と鉱脈を置く。
    /// 超えるときは地形を必要なときに計算し、POI と鉱脈は拠点まわりのチャンクから順に置く(原作のチャンク遅延生成)。
    public var denseCellLimit: Int
    /// POI と鉱脈を置く単位(原作 64)。
    public var chunkSize: Int
    /// チャンクを 8×8 の区画に分け、区画ごとにこの確率で POI を置く(原作 16%)。
    public var poiPercentPerCell: Int
    /// 区画ごとに鉱脈を置こうとする確率。
    public var depositPercentPerCell: Int
    /// 拠点の整地からこの距離の内側には POI を置かない。
    public var poiBaseExclusion: Int
    /// 小さい地図で遺跡が少なすぎるとき、いちばん汚れたあたりに遺跡の塊を足す(5 バイオームを揃える)。
    public var minimumRuinsCells: Int
    /// 生成のやり直しの上限(位置関係の保証を満たすまで)。
    public var maxLayoutAttempts: Int
    /// やり直しの上限に達したとき、未検証の地図を返す(記録に verified = false を残す)。既定は投げる。
    public var allowUnverifiedFallback: Bool
    public var vision: VisionRule
    /// コンテンツが決める場所(砦など。U16)。nil・空なら何も置かず、乱数も引かない。
    public var sites: [SiteRule]?

    public init(size: MapSize, landmarks: LandmarkRules? = nil, biomes: BiomeThresholds? = nil, denseCellLimit: Int = 1 << 20,
                chunkSize: Int = 64, poiPercentPerCell: Int = 16, depositPercentPerCell: Int = 12,
                poiBaseExclusion: Int = 6, minimumRuinsCells: Int = 12, maxLayoutAttempts: Int = 64,
                allowUnverifiedFallback: Bool = false, vision: VisionRule = .original) {
        self.size = size
        self.landmarks = (landmarks ?? .r1).scaled(to: size)
        // 小さい地図(R1 の 96×96 前後)は R1 の閾値、原作の大きさは原作の閾値
        self.biomes = biomes ?? (size.cellCount <= 256 * 256 ? .r1 : .original)
        self.denseCellLimit = denseCellLimit
        self.chunkSize = chunkSize
        self.poiPercentPerCell = poiPercentPerCell
        self.depositPercentPerCell = depositPercentPerCell
        self.poiBaseExclusion = poiBaseExclusion
        self.minimumRuinsCells = minimumRuinsCells
        self.maxLayoutAttempts = maxLayoutAttempts
        self.allowUnverifiedFallback = allowUnverifiedFallback
        self.vision = vision
    }

    /// 目印を置ける最小の短い辺。
    public static let minimumSide = 48

    /// R1 の地図(96×96)。
    public static let r1 = MapGenerationConfig(size: .r1)
    /// 原作の大きさ(10000×10000。地形は必要なときに計算する)。
    public static let original = MapGenerationConfig(size: .original)
}
