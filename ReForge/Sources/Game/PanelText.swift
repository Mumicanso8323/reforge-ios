/// 残骸のパネルの数の言い回し。担当: U18。
enum PanelText {
    /// 千分率 → 「4%」「35%」(小数は 1 桁まで、0 は落とす)。
    static func percent(_ permille: Int) -> String {
        let p = max(0, permille)
        return p % 10 == 0 ? "\(p / 10)%" : "\(p / 10).\(p % 10)%"
    }
}
