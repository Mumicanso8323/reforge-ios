import SwiftUI
import ReForgeEngine

/// 下のタブ。担当: U18(解放の条件で出し入れする)。見た目は art-director の Theme。
enum GameTab: String, CaseIterable, Identifiable {
    case map, design, notes, base, crew
    var id: String { rawValue }
}

/// 下のタブ(地図・設計・ノート・拠点・仲間)。
struct TabBarView: View {
    @Binding var tab: GameTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(GameTab.allCases) { t in
                Button {
                    tab = t
                } label: {
                    title(t)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(tab == t ? InkColor.text : InkColor.textDim)
                        .overlay(alignment: .top) {
                            // いま開いているタブにだけ錆の線
                            Rectangle().fill(tab == t ? InkColor.accent : .clear).frame(height: 2)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tab-\(t.rawValue)")
            }
        }
        .font(InkFont.body)
        .background(InkColor.ground)
        .overlay(alignment: .top) {
            Rectangle().fill(InkColor.rule).frame(height: InkMetric.rule)
        }
    }

    @ViewBuilder private func title(_ t: GameTab) -> some View {
        switch t {
        case .map: Text("地図")
        case .design: Text("設計")
        case .notes: Text("ノート")
        case .base: Text("拠点")
        case .crew: Text("仲間")
        }
    }
}
