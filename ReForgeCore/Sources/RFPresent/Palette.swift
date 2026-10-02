import RFKernel
import RFMap

/// 色(0...255)。SwiftUI の Color に依存しない(Linux でテストできるように)。
public struct RGB: Hashable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8

    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// 明るさを掛ける(既知の暗い地形・夜)。
    public func scaled(_ k: Double) -> RGB {
        func s(_ v: UInt8) -> UInt8 { UInt8(max(0, min(255, (Double(v) * k).rounded()))) }
        return RGB(s(r), s(g), s(b))
    }

    public static let black = RGB(0, 0, 0)
}

/// 1 マスの色(文字の色の候補と、あれば背景)。
public struct TileStyle: Hashable, Sendable {
    /// 文字の色の候補(座標で 1 つを選ぶ。土色各種のような揺らぎ)。
    public var foreground: [RGB]
    /// 背景(水辺の青など)。nil は黒。
    public var background: RGB?

    public init(foreground: [RGB], background: RGB? = nil) {
        self.foreground = foreground
        self.background = background
    }

    public func foreground(at p: GridPoint) -> RGB {
        foreground.isEmpty ? RGB(200, 200, 200) : foreground[TilePalette.spread(p) % foreground.count]
    }
}

/// 地図の色の表(原作 MapScreen.cs の色と、order.md §5.5 のパレット)。黒地に色つきの文字。
/// 地形の色は地形の ID と性質(TerrainDef の isWater・tags)から決める。文字(glyph)は認識の層が決める。
public enum TilePalette {
    // 色の名前(TileView.tint)
    public static let void = "void"
    public static let hint = "hint"
    public static let poi = "poi"
    public static let noah = "noah"
    public static let member = "member"
    public static let stranger = "stranger"
    public static let enemy = "enemy"
    public static let module = "module"
    public static let stopped = "stopped"
    public static let route = "route"
    public static func terrain(_ id: TerrainID) -> String { "terrain." + id.rawValue }
    /// 鉱脈の色の鍵(鉱脈の種類 DepositCategory の名前)。
    public static func deposit(_ category: String) -> String { "deposit." + category }

    // 原作の色
    static let ground = [RGB(110, 95, 75), RGB(125, 110, 85), RGB(95, 85, 70)]
    static let grass = [RGB(80, 140, 70), RGB(110, 150, 60), RGB(60, 110, 60), RGB(90, 130, 80), RGB(100, 160, 80)]
    static let forest = [RGB(40, 100, 45), RGB(55, 120, 55), RGB(70, 135, 65)]
    static let water = [RGB(70, 110, 180), RGB(70, 110, 180), RGB(70, 110, 180), RGB(130, 170, 220)]
    static let waterBackground = RGB(30, 50, 90)
    static let rock = [RGB(120, 115, 105), RGB(100, 95, 88)]
    static let ruin = [RGB(110, 105, 95), RGB(80, 75, 65)]
    static let cleared = [RGB(170, 150, 110), RGB(155, 135, 100)]
    static let metal = [RGB(150, 155, 165), RGB(90, 95, 105)]
    static let oreIron = RGB(180, 100, 70)
    static let oreCopper = RGB(70, 160, 140)
    static let oreOther = RGB(160, 100, 200)

    /// 夜の明るさ(視界の中)。
    public static let nightVisible = 0.75
    /// 既知だが視界の外(暗い地形だけ)。
    public static let remembered = 0.42

    public static func style(_ tint: String, terrains: [TerrainID: TerrainDef]) -> TileStyle {
        switch tint {
        case void: return TileStyle(foreground: [.black])
        case hint: return TileStyle(foreground: [RGB(85, 85, 100)])
        case poi: return TileStyle(foreground: metal)
        case noah: return TileStyle(foreground: [RGB(255, 255, 100)])
        case member: return TileStyle(foreground: [RGB(230, 210, 170)])
        case stranger: return TileStyle(foreground: [RGB(200, 190, 170)])
        case enemy: return TileStyle(foreground: [RGB(170, 55, 55)])  // 暗い赤(予約の鮮やかな赤と見分ける)
        case module: return TileStyle(foreground: [RGB(220, 200, 60)])
        case stopped: return TileStyle(foreground: [RGB(150, 72, 72)])  // くすんだ赤(予約の鮮やかな赤と見分ける)
        case route: return TileStyle(foreground: [RGB(200, 200, 100)])
        default: break
        }
        if tint.hasPrefix("deposit.") {
            let ore = tint.dropFirst("deposit.".count)
            if ore.contains("copper") { return TileStyle(foreground: [oreCopper]) }
            if ore.contains("iron") { return TileStyle(foreground: [oreIron]) }
            return TileStyle(foreground: [oreOther])
        }
        if tint.hasPrefix("terrain.") {
            let raw = String(tint.dropFirst("terrain.".count))
            let def = terrains[TerrainID(rawValue: raw)]
            let words = Set((def?.tags ?? []) + [raw])
            if def?.isWater == true || words.contains("water") {
                return TileStyle(foreground: water, background: waterBackground)
            }
            if words.contains("rock") { return TileStyle(foreground: rock) }
            if words.contains("forest") { return TileStyle(foreground: forest) }
            if words.contains("ruins") || words.contains("wreck") { return TileStyle(foreground: ruin) }
            if words.contains("cleared") || words.contains("base") { return TileStyle(foreground: cleared) }
            if words.contains("grass") || words.contains("grassland") { return TileStyle(foreground: grass) }
            return TileStyle(foreground: ground)
        }
        return TileStyle(foreground: [RGB(200, 200, 200)])
    }

    /// 座標の揺らぎ(原作 MapScreen.HashCoord と同じ式。同じマスは常に同じ見た目)。
    public static func hash(_ p: GridPoint) -> Int {
        var h: Int32 = Int32(bitPattern: 2_166_136_261)
        h = (h ^ Int32(truncatingIfNeeded: p.x)) &* 16_777_619
        h = (h ^ Int32(truncatingIfNeeded: p.y)) &* 16_777_619
        h = (h ^ Int32(truncatingIfNeeded: p.x &* 31 &+ p.y &* 17)) &* 16_777_619
        return Int(h & 0x7FFF_FFFF)
    }

    /// 候補を選ぶ添字(hash の下位ビットは偶奇が座標によらず揃うので、上の方のビットを使う)。
    public static func spread(_ p: GridPoint) -> Int { (hash(p) >> 8) % 1009 }

    /// 地図の文字が複数の候補を持つとき(地面の `. ,`)、座標で 1 つを選ぶ。空白は候補にしない。
    public static func pickGlyph(_ glyph: String, at p: GridPoint) -> String {
        let options = glyph.filter { !$0.isWhitespace }
        guard options.count > 1 else { return options.isEmpty ? glyph : String(options) }
        let chars = Array(options)
        return String(chars[spread(p) % chars.count])
    }
}
