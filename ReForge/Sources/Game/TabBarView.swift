import SwiftUI
import ReForgeEngine

/// 下のタブ。担当: U18(解放の条件で出し入れする)。見た目は art-director の Theme。
enum GameTab: String, CaseIterable, Identifiable {
    case map, design, notes, base, crew
    var id: String { rawValue }

    /// 解放の条件の要素(地図はいつも出す)。
    var element: UIElementID? {
        switch self {
        case .map: nil
        case .design: UIElements.tabDesign
        case .notes: UIElements.tabNotes
        case .base: UIElements.tabBase
        case .crew: UIElements.tabCrew
        }
    }

    /// タブの名前(文言の表から。ID は静的に書く)。`ui` が MainActor なので、ここも MainActor(`visible` などは分離の外のまま)。
    @MainActor var title: Text {
        switch self {
        case .map: ui("ui.tab.map")
        case .design: ui("ui.tab.design")
        case .notes: ui("ui.tab.notes")
        case .base: ui("ui.tab.base")
        case .crew: ui("ui.tab.crew")
        }
    }

    /// いま出すタブ(A Dark Room 式: 最初は地図だけ。条件が成り立ったタブから増える)。
    static func visible(_ ui: UIUnlocks) -> [GameTab] {
        allCases.filter { $0.element.map(ui.isOpen) ?? true }
    }
}

/// 下のタブ(地図・設計・ノート・拠点・仲間)。出ているタブが地図だけのときは帯ごと出さない。
struct TabBarView: View {
    @Binding var tab: GameTab
    var ui = UIUnlocks()

    var body: some View {
        let tabs = GameTab.visible(ui)
        if tabs.count > 1 {
            InkBand(edge: .top) {
                HStack(spacing: 0) {
                    ForEach(tabs) { t in
                        Button {
                            tab = t
                        } label: {
                            t.title
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(Rectangle())
                                .foregroundStyle(tab == t ? InkColor.accent : InkColor.textDim)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("tab-\(t.rawValue)")
                    }
                }
                .font(InkFont.body)
            }
        }
    }
}
