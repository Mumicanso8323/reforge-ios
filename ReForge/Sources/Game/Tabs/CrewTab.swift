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
        InkPanel(title: ui("ui.tab.crew")) {
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
                    InkSection(title: ui("ui.body.stance_section")) {
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

    /// 「種類 対象 ・ 動作 ・ 状態」の 1 行。つなぎ(空白・「・」)は表の 1 つの文が持つ。
    private func summary(_ m: CrewMemberView) -> Text {
        let conditions = m.body.conditions.joined(separator: UIText.shared.string("ui.body.list_sep"))
        return ui("ui.body.crew_summary", [
            "kind": .string(AssignText.kindString(m.assignment)),
            "hasTarget": .string(m.target == nil ? "no" : "yes"),
            "target": .string(m.target ?? ""),
            "doing": .string(AssignText.doingString(m.doing)),
            "hasConditions": .string(m.body.conditions.isEmpty ? "no" : "yes"),
            "conditions": .string(conditions),
        ])
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
                        ui("ui.button.assign_chip", [
                            "kind": .string(AssignText.kindString(c.kind)),
                            "hasTarget": .string(c.target == nil ? "no" : "yes"),
                            "target": .string(c.target ?? ""),
                        ])
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
            gauge(ui("ui.body.vital_health"), vitals.health)
            gauge(ui("ui.body.vital_stamina"), vitals.stamina)
            gauge(ui("ui.body.vital_satiety"), vitals.satiety)
            gauge(ui("ui.body.vital_hydration"), vitals.hydration)
            gauge(ui("ui.body.vital_mind"), vitals.mind)
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

/// 割り当て・動作・構えの固定文言(文言の表から。ID は列挙型ごとに静的に書く)。
@MainActor
enum AssignText {
    static func kindString(_ k: CrewMemberView.AssignKind) -> String {
        switch k {
        case .idle: UIText.shared.string("ui.button.assign_idle")
        case .gather: UIText.shared.string("ui.button.assign_gather")
        case .haul: UIText.shared.string("ui.button.assign_haul")
        case .operate: UIText.shared.string("ui.button.assign_operate")
        case .research: UIText.shared.string("ui.button.assign_research")
        case .guardArea: UIText.shared.string("ui.button.assign_guard")
        case .build: UIText.shared.string("ui.button.assign_build")
        case .rest: UIText.shared.string("ui.button.assign_rest")
        case .follow: UIText.shared.string("ui.button.assign_follow")
        }
    }

    static func kind(_ k: CrewMemberView.AssignKind) -> Text { Text(verbatim: kindString(k)) }

    static func doingString(_ d: CrewMemberView.Doing) -> String {
        switch d {
        case .idle: UIText.shared.string("ui.body.doing_idle")
        case .walking: UIText.shared.string("ui.body.doing_walking")
        case .working: UIText.shared.string("ui.body.doing_working")
        case .carrying: UIText.shared.string("ui.body.doing_carrying")
        case .gathering: UIText.shared.string("ui.body.doing_gathering")
        case .fighting: UIText.shared.string("ui.body.doing_fighting")
        case .sleeping: UIText.shared.string("ui.body.doing_sleeping")
        case .talking: UIText.shared.string("ui.body.doing_talking")
        case .guarding: UIText.shared.string("ui.body.doing_guarding")
        }
    }

    static func doing(_ d: CrewMemberView.Doing) -> Text { Text(verbatim: doingString(d)) }

    static func stance(_ s: BattleState.Stance) -> Text {
        switch s {
        case .advance: ui("ui.button.stance_advance")
        case .keepDistance: ui("ui.button.stance_keep_distance")
        }
    }
}
