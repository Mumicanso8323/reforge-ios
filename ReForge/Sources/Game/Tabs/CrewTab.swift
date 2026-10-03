import SwiftUI
import ReForgeEngine

/// 仲間のタブ(割り当て・体の状態・関係)。担当: U18。
/// 遊びの中心は「住人を割り当てて自動化する」こと。1 人を選び、下の札を 1 回押せば割り当てが変わる(確認なし)。
/// 名前・対象はすべて本体の射影(CrewView)が認識の層を通して渡す。
struct CrewTabView: View {
    @Bindable var app: AppModel
    let store: GameStore
    @State private var crew: CrewView?
    @State private var selected: PersonID?

    var body: some View {
        InkPanel(title: Text("仲間")) {
            if let crew {
                InkSection {
                    ForEach(crew.members, id: \.id) { m in
                        Button { selected = selected == m.id ? nil : m.id } label: {
                            InkRow(glyph: m.glyph, title: Text(verbatim: m.name), detail: summary(m),
                                   value: relation(m), selected: selected == m.id)
                        }
                        .buttonStyle(.inkRow)
                        .accessibilityIdentifier("crew-\(m.id.rawValue)")
                        if selected == m.id {
                            if let a = m.art {
                                // 立ち絵の全身(11:25 のまま縮める。絵が無ければ ArtView は場所を取らない)
                                ArtView(id: a)
                                    .frame(maxWidth: 160, maxHeight: 364)
                                    .frame(maxWidth: .infinity)
                            }
                            BodyGauges(vitals: m.body)
                            if store.ui.isOpen(UIElements.crewAssign) {
                                AssignChips(member: m, choices: m.choices, store: store)
                            }
                        }
                    }
                }
                if store.ui.isOpen(UIElements.combatStance) {
                    InkSection(title: Text("戦いの構え(寝ている間も)")) {
                        StancePicker(current: store.defaultStance) { store.setDefaultStance($0) }
                    }
                }
            }
        }
        .task(id: store.revision) {
            let c = await store.host.crew()
            crew = c
            if selected == nil { selected = c.members.first { !$0.isNoah }?.id ?? c.members.first?.id }
        }
        .accessibilityIdentifier("crewTab")
    }

    private func summary(_ m: CrewMemberView) -> Text {
        var t = AssignText.kind(m.assignment)
        if let target = m.target { t = t + Text(verbatim: " ") + Text(verbatim: target) }
        t = t + Text(verbatim: " ・ ") + AssignText.doing(m.doing)
        if !m.body.conditions.isEmpty { t = t + Text(verbatim: " ・ " + m.body.conditions.joined(separator: "・")) }
        return t
    }

    private func relation(_ m: CrewMemberView) -> Text? {
        guard !m.isNoah, store.ui.isOpen(UIElements.crewRelation) else { return nil }
        return Text("♥\(m.relationRank)")
    }
}

/// 割り当ての札(横に並べる。押せばすぐ変わる)。種類ごとに解放の条件で出し入れする。
struct AssignChips: View {
    let member: CrewMemberView
    let choices: [AssignChoice]
    let store: GameStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: InkMetric.gap) {
                ForEach(Array(visible.enumerated()), id: \.offset) { _, c in
                    Button { store.send(c.command(for: member.id)) } label: {
                        Text(verbatim: "") + AssignText.kind(c.kind) + Text(verbatim: c.target.map { " " + $0 } ?? "")
                    }
                    .buttonStyle(.ink(isCurrent(c) ? .primary : .secondary, fill: false))
                }
            }
            .padding(.vertical, 6)
        }
        .accessibilityIdentifier("assignChips")
    }

    private var visible: [AssignChoice] {
        choices.filter { store.ui.isOpen(UIElements.assign($0.kind.rawValue)) && !(member.isNoah && $0.kind == .follow) }
    }

    private func isCurrent(_ c: AssignChoice) -> Bool {
        c.kind == member.assignment && (c.target == nil || c.target == member.target)
    }
}

/// 体の値(千分率)を文字の棒で出す(文字グラフィックス)。
struct BodyGauges: View {
    let vitals: CrewMemberView.Body

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            gauge(Text("体力"), vitals.health)
            gauge(Text("気力"), vitals.stamina)
            gauge(Text("満腹"), vitals.satiety)
            gauge(Text("水分"), vitals.hydration)
            gauge(Text("心"), vitals.mind)
        }
        .font(InkFont.small)
        .padding(.vertical, 6)
    }

    private func gauge(_ label: Text, _ permille: Int) -> some View {
        HStack(spacing: 8) {
            label.frame(width: 44, alignment: .leading).foregroundStyle(InkColor.textDim)
            Text(verbatim: TextBar.bar(permille, width: 10))
                .foregroundStyle(permille < 300 ? InkColor.alert : InkColor.text)
        }
    }
}

/// 文字の棒(■■■□□)。
enum TextBar {
    static func bar(_ permille: Int, width: Int) -> String {
        let n = max(0, min(width, (permille * width + 500) / 1000))
        return String(repeating: "■", count: n) + String(repeating: "□", count: width - n)
    }
}

/// 前に出る / 距離を取る。
struct StancePicker: View {
    let current: BattleState.Stance
    let choose: (BattleState.Stance) -> Void

    var body: some View {
        HStack(spacing: InkMetric.gap) {
            ForEach([BattleState.Stance.advance, .keepDistance], id: \.self) { s in
                Button { choose(s) } label: { AssignText.stance(s) }
                    .buttonStyle(.ink(current == s ? .primary : .secondary, fill: false))
            }
        }
        .padding(.vertical, 6)
    }
}

/// 割り当て・動作・構えの固定文言。
enum AssignText {
    static func kind(_ k: CrewMemberView.AssignKind) -> Text {
        switch k {
        case .idle: Text("空き")
        case .gather: Text("採取")
        case .haul: Text("運搬")
        case .operate: Text("持ち場")
        case .research: Text("研究")
        case .guardArea: Text("見張り")
        case .build: Text("建造")
        case .rest: Text("休む")
        case .follow: Text("ついて行く")
        }
    }

    static func doing(_ d: CrewMemberView.Doing) -> Text {
        switch d {
        case .idle: Text("待っている")
        case .walking: Text("歩いている")
        case .working: Text("働いている")
        case .carrying: Text("運んでいる")
        case .gathering: Text("採っている")
        case .fighting: Text("戦っている")
        case .sleeping: Text("眠っている")
        case .talking: Text("話している")
        case .guarding: Text("見張っている")
        }
    }

    static func stance(_ s: BattleState.Stance) -> Text {
        switch s {
        case .advance: Text("前に出る")
        case .keepDistance: Text("距離を取る")
        }
    }
}
