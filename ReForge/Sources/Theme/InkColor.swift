import SwiftUI
import ReForgeEngine

/// 画面の色(docs/art/README.md §1)。地は「墨」の暗い藍、文字は生成りの紙色、差し色は錆。赤は 2 種類(ふつうの赤 alert と、予約の赤 reserved)。
/// 遊びの面(地図・品物の名前)の色は ReForgeCore の RFPresent が決める(TilePalette)。ここは画面の部品の色だけ。
enum InkColor {
    // 地
    /// 遊びの面の地(地図の下)。原作どおりの黒。
    static let field = Color.black
    /// 序の場面だけの地(PT-B6)。画面全体を覆う語りの地。黒(field)ともふつうの地(ground)とも違う、ごく暗い藍。
    static let prologueGround = Color(red: 0.027, green: 0.031, blue: 0.047)
    /// 画面の地(帯・札・パネルの外側)。
    static let ground = Color(red: 0.067, green: 0.075, blue: 0.098)
    /// パネルの地(一段持ち上がった面)。
    static let panel = Color(red: 0.106, green: 0.118, blue: 0.153)
    /// 押せる物の地・選んでいる行の地。
    static let raised = Color(red: 0.165, green: 0.180, blue: 0.227)
    /// 罫線(1pt)。
    static let rule = Color(red: 0.255, green: 0.271, blue: 0.325)

    // 文字
    /// 本文(生成り)。
    static let text = Color(red: 0.902, green: 0.875, blue: 0.816)
    /// 補助(ラベル・単位)。
    static let textDim = Color(red: 0.600, green: 0.592, blue: 0.565)
    /// 押せない・まだ無い。
    static let textFaint = Color(red: 0.400, green: 0.400, blue: 0.400)

    // 差し色(画面に 1 つ。主の行為と、いま選んでいる物)
    /// 錆。主ボタンの地・選んでいるタブ。
    static let accent = Color(red: 0.722, green: 0.420, blue: 0.282)
    /// 錆の地の上の文字。
    static let onAccent = Color(red: 0.067, green: 0.075, blue: 0.098)

    // 意味の色(文字にだけ使う。地には塗らない)
    /// 断られた・足りない(足元カードの 1 行)。
    static let notice = Color(red: 0.961, green: 0.702, blue: 0.459)
    /// 危ない(残り日数が少ない・壊す行為)。ふつうの赤(橙に寄せてくすませた赤。予約の赤と明るさで見分けられる)。
    static let alert = Color(red: 0.843, green: 0.529, blue: 0.373)
    /// 動いている・できた。
    static let good = Color(red: 0.588, green: 0.784, blue: 0.565)
    /// 夜。
    static let night = Color(red: 0.459, green: 0.518, blue: 0.784)
    /// 夕方・昼の残り。
    static let dusk = Color(red: 0.902, green: 0.722, blue: 0.392)

    // 予約
    /// 鮮やかな赤。予約された特別な用途のための色で、ゲームの中でいちばん目立つ赤。
    /// ほかの用途には使わない。使う場所は、決まるまで作らない。
    static let reserved = Color(red: 0.941, green: 0.157, blue: 0.235)
}

extension Color {
    /// 本体の色(RFPresent.RGB)を SwiftUI の色にする。遊びの面の色はこれで通す。
    init(rgb: RGB) {
        self.init(red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255)
    }
}
