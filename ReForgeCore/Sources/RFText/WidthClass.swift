import RFKernel

/// 文言ごとの「幅の区分」(L-13。設計書 §11)。文が長くなっても壊れない配置の規則を、区分で決める。
/// 値は整数だけ(浮動小数を本体に持ち込まない)。幅は標準の大きさの文字で測る(大きい文字は範囲の外)。
public enum WidthClass: String, CaseIterable, Sendable {
    case button, band, tab, card, bubble, prologue, label, body

    /// 縮小の下限(% の整数)。アプリで 0.85 に直す定数は 1 か所(InkMetric.minimumScale)。
    public static let minimumScale = 85

    /// 字の大きさ(pt)。
    public var pointSize: Int {
        switch self {
        case .button: return 16
        case .band: return 14
        case .tab: return 12
        case .card: return 15
        case .bubble: return 14
        case .prologue: return 17
        case .label: return 12
        case .body: return 15
        }
    }

    /// 幅の上限(pt)。無ければ nil。幅の基準は最小の画面幅 375pt から左右 16pt を引いた 343pt。
    public var maxWidth: Int? {
        switch self {
        case .button: return 150
        case .band: return 110
        case .tab: return 64
        case .card: return 343
        case .bubble: return 260
        case .prologue: return 310
        case .label: return 120
        case .body: return 343
        }
    }

    /// 行の上限。無ければ nil。prologue は 1 文が 2 行まで。
    public var maxLines: Int? {
        switch self {
        case .button, .band, .tab, .label: return 1
        case .card, .prologue: return 2
        case .bubble: return 4
        case .body: return nil
        }
    }

    /// 0.85 倍まで縮めてよい(button・band だけ)。
    public var shrinkable: Bool {
        self == .button || self == .band
    }

    /// 文が伸びたら箱が伸びる(card・bubble・prologue・body)。
    public var growsWithText: Bool {
        switch self {
        case .card, .bubble, .prologue, .body: return true
        case .button, .band, .tab, .label: return false
        }
    }

    /// 文言の ID の頭 `ui.<区分>.` から区分を決める。合わない ID(本体の `ui.daywrap.*` など)と
    /// `ui.a11y.*` は .body(読み上げ専用は測らない)。
    public static func of(_ id: TextID) -> WidthClass {
        let parts = id.rawValue.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3, parts[0] == "ui", let found = WidthClass(rawValue: String(parts[1])) else {
            return .body
        }
        return found
    }
}
