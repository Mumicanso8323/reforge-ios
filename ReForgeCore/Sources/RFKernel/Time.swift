/// ゲーム内の時刻。ゲーム開始からの経過ゲーム秒(整数)。壁時計は読まない。
public struct GameTime: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public var seconds: Int64

    public init(seconds: Int64) { self.seconds = seconds }

    public static let zero = GameTime(seconds: 0)
    public static func < (a: Self, b: Self) -> Bool { a.seconds < b.seconds }
    public static func + (t: Self, d: GameDuration) -> Self { GameTime(seconds: t.seconds + d.seconds) }
    public static func - (a: Self, b: Self) -> GameDuration { GameDuration(seconds: a.seconds - b.seconds) }
    public var description: String { "t\(seconds)" }

    public init(from decoder: Decoder) throws { seconds = try decoder.singleValueContainer().decode(Int64.self) }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(seconds)
    }
}

public struct GameDuration: Hashable, Comparable, Codable, Sendable {
    public var seconds: Int64

    public init(seconds: Int64) { self.seconds = seconds }
    public static func minutes(_ m: Int) -> Self { Self(seconds: Int64(m) * 60) }
    public static func hours(_ h: Int) -> Self { Self(seconds: Int64(h) * 3600) }
    public static func < (a: Self, b: Self) -> Bool { a.seconds < b.seconds }

    public init(from decoder: Decoder) throws { seconds = try decoder.singleValueContainer().decode(Int64.self) }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(seconds)
    }
}

/// シミュレーションの固定ステップ。昼のリアルタイムも夜の一括も、同じ幅のステップを同じ関数で進める
/// (だから「昼をリアルタイムで過ごす」と「同じ時間をまとめて進める」の結果が一致する。C-engine-ui.md §3)。
public enum SimStep {
    /// 1 ステップのゲーム秒。昼 180 実秒 = 8 ゲーム時間なら 1 実秒あたり 10.7 ステップ。
    public static let gameSeconds: Int64 = 15
    public static let duration = GameDuration(seconds: gameSeconds)
}
