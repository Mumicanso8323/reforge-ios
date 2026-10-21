import SwiftUI
import ReForgeEngine

/// 拠点のタブ(蓄え・建てた物・建てる・運搬・研究・セーブ)。担当: U18。
/// 名前はすべて本体の射影(BaseView・ResearchView)が認識の層を通して渡す。ここに物語の文は書かない。
/// 各まとまりは解放の条件(UIElements)で出し入れする。
struct BaseTabView: View {
    @Bindable var app: AppModel
    let store: GameStore
    @State private var base: BaseView?
    @State private var research: ResearchView?
    @State private var groups = SavePointGroups(auto: [], manual: [])

    var body: some View {
        InkPanel(title: ui("ui.tab.base")) {
            if let base {
                if store.ui.isOpen(UIElements.baseStock) { stock(base) }
                built(base)
                if store.ui.isOpen(UIElements.baseBuild), !base.buildable.isEmpty || !base.shadows.isEmpty || base.unknownStructures > 0 { build(base) }
                if store.ui.isOpen(UIElements.baseLines), !base.lines.isEmpty { lines(base) }
            }
            if store.ui.isOpen(UIElements.research), let research, !research.entries.isEmpty || research.hiddenCount > 0 {
                ResearchSection(view: research, store: store)
                    .id("researchSection")
            }
            if store.ui.isOpen(UIElements.saveManual) { saves }
            InkSection {
                Button { Task { await app.backToTitle() } } label: { ui("ui.button.to_title") }
                    .buttonStyle(.ink(.quiet))
            }
            #if DEBUG
            // 研究の写真だけ: 研究の節を上へ送れるだけの余白(内容が短いと、拠点の見出しが帯の下に半分残って写る)
            if ScreenshotMode.screen == .research { Color.clear.frame(height: 400) }
            #endif
        }
        .task(id: store.revision) {
            base = await store.host.base()
            research = await store.host.research()
            groups = store.savePointGroups(activeOnly: false)
        }
        .accessibilityIdentifier("baseTab")
        #if DEBUG
        .modifier(ResearchSectionScrollModifier(researchLoaded: research != nil))
        #endif
    }

    private func stock(_ v: BaseView) -> some View {
        InkSection(title: ui("ui.body.stock")) {
            if v.stock.isEmpty {
                InkRow(title: ui("ui.body.stock_empty")).foregroundStyle(InkColor.textDim)
            }
            ForEach(v.stock, id: \.name) { s in
                InkRow(title: spokenText(s.name), value: Text(verbatim: "\(s.quantity)"))
            }
        }
    }

    private func built(_ v: BaseView) -> some View {
        InkSection(title: ui("ui.body.built")) {
            ForEach(v.built, id: \.id) { b in
                let row = InkRow(glyph: b.glyph, title: spokenText(b.name), detail: detail(b), value: state(b.state))
                if case .blocked = b.state {
                    row.accessibilityLabel(ui("ui.a11y.blocked"))
                } else {
                    row
                }
            }
        }
    }

    private func detail(_ b: BaseView.Built) -> Text? {
        b.workers.isEmpty ? nil : spokenText(b.workers.joined(separator: UIText.shared.string("ui.body.list_sep")))
    }

    private func state(_ s: BaseView.Built.State) -> Text {
        switch s {
        case .running: ui("ui.body.state_running")
        case .building(let p): ui("ui.body.state_building", ["percent": .int(p / 10)])
        case .stopped(let r): spokenText(r)
        case .blocked:
            Text("■").foregroundStyle(InkColor.alert)
        case .broken: ui("ui.body.state_broken")
        }
    }

    /// 建てる: 選ぶと地図に戻り、次にタップしたマスに建てる(確認は出さない。片付ければ材料は戻る)。
    private func build(_ v: BaseView) -> some View {
        InkSection(title: ui("ui.body.build")) {
            ForEach(v.buildable, id: \.kind) { o in
                switch BuildRowKind.of(o) {
                case .button:
                    Button {
                        store.beginPlacing(o.kind)
                    } label: {
                        InkRow(glyph: o.glyph, title: spokenText(o.name),
                               detail: spokenText(Self.price(o)),
                               selected: store.placing == o.kind)
                    }
                    .buttonStyle(.inkRow)
                    .accessibilityIdentifier("build-\(o.kind.rawValue)")
                case .plain:
                    InkRow(glyph: o.glyph, title: spokenText(o.name), detail: spokenText(Self.price(o)))
                        .foregroundStyle(InkColor.textDim)
                        .accessibilityValue(ui("ui.a11y.unavailable"))
                }
            }
            let unknownCount = v.unknownStructures + v.shadows.count
            if unknownCount > 0 {
                InkRow(title: ui("ui.body.unknown_structures", ["n": .int(unknownCount)]))
                    .foregroundStyle(InkColor.textDim)
                    .accessibilityIdentifier("buildUnknown")
            }
        }
    }

    /// 必要な材料の値札(足りているかで文を変えない。押せない物は押せない形にするだけ)。
    @MainActor private static func price(_ option: BaseView.BuildOption) -> String {
        let cost = option.cost.map {
            UIText.shared.string("ui.body.cost_item", ["name": .string($0.name), "quantity": .int($0.quantity)])
        }.joined(separator: UIText.shared.string("ui.body.cost_sep"))
        return UIText.shared.string("ui.body.price", ["cost": .string(cost)])
    }

    private func lines(_ v: BaseView) -> some View {
        InkSection(title: ui("ui.body.lines")) {
            ForEach(v.lines, id: \.id) { l in
                InkRow(glyph: "→", title: spokenText("\(l.from) → \(l.to)"),
                       detail: l.blocked.map { spokenText($0) }
                           ?? (l.haulers.isEmpty ? nil : spokenText(l.haulers.joined(separator: UIText.shared.string("ui.body.list_sep")))),
                       value: ui("ui.body.moved_yesterday", ["n": .int(l.movedYesterday)]))
            }
        }
    }

    /// 記録: 夜明けの記録(自動。読むだけ)と自分の記録(手動 3 枠。確認なしで上書き。中身があれば読める)の 2 つの節。
    private var saves: some View {
        let readableAuto = groups.readable.auto.filter { $0.summary?.active == true }
        return VStack(alignment: .leading, spacing: InkMetric.gap) {
            if !readableAuto.isEmpty {
                InkSection(title: ui("ui.body.records_auto")) {
                    ForEach(readableAuto, id: \.slot) { p in
                        Button {
                            Task { await store.load(p.slot) }
                        } label: {
                            InkRow(title: slotText(p.slot), value: ui("ui.button.save_read"))
                        }
                        .buttonStyle(.inkRow)
                    }
                }
            }
            InkSection(title: ui("ui.body.records_manual")) {
                ForEach(0..<SavePolicy.manualSlots, id: \.self) { i in
                    let existing = groups.manual.first { $0.slot == .manual(index: i) }?.summary
                    HStack(spacing: InkMetric.gap) {
                        InkRow(title: slotText(.manual(index: i)),
                               value: existing.map { ui("ui.body.slot_day", ["day": .int($0.day)]) } ?? ui("ui.body.slot_empty"))
                        // 空きと終わった走行の枠には「読む」を置かない(押せない物はボタンにしない)
                        if existing?.active == true {
                            Button {
                                Task { await store.load(.manual(index: i)) }
                            } label: { ui("ui.button.save_read") }
                                .buttonStyle(.ink(.secondary, fill: false))
                                .accessibilityIdentifier("read-\(i)")
                        }
                        Button {
                            Task {
                                await store.saveManual(i)
                                groups = store.savePointGroups(activeOnly: false)
                            }
                        } label: { ui("ui.button.save_write") }
                            .buttonStyle(.ink(.secondary, fill: false))
                            .accessibilityIdentifier("save-\(i)")
                    }
                }
            }
        }
    }
}

#if DEBUG
private struct ResearchSectionScrollModifier: ViewModifier {
    let researchLoaded: Bool

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content.onChange(of: researchLoaded) { _, loaded in
                guard loaded, ScreenshotMode.screen == .research else { return }
                Task { @MainActor in
                    for _ in 0..<10 {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        guard !Task.isCancelled else { return }
                        proxy.scrollTo("researchSection", anchor: .top)
                    }
                }
            }
        }
    }
}
#endif

/// 研究: 選ぶ(別のを選べば切り替わる。進みは残る)と進み具合。
struct ResearchSection: View {
    let view: ResearchView
    let store: GameStore

    var body: some View {
        InkSection(title: ui("ui.body.research")) {
            ForEach(view.entries, id: \.id) { e in
                // 選べる物だけをボタンにする(解けていない・済んだ・区切りで待っている間は行だけ。Z1)
                if !view.held, e.status == .available || e.status == .active {
                    Button { store.send(e.selectCommand) } label: { row(e) }
                        .buttonStyle(.inkRow)
                        .accessibilityIdentifier("research-\(e.id.rawValue)")
                } else {
                    row(e)
                        .foregroundStyle(e.status == .locked ? InkColor.textDim : InkColor.text)
                        .accessibilityIdentifier("research-\(e.id.rawValue)")
                }
            }
            if view.hiddenCount > 0 {
                // 深さの気配: 名前は出さず、数だけ(§10 HNT-16)
                InkRow(title: ui("ui.body.research_hidden", ["n": .int(view.hiddenCount)]))
                    .foregroundStyle(InkColor.textDim)
                    .accessibilityIdentifier("researchHidden")
            }
        }
    }

    private func row(_ e: ResearchView.Entry) -> InkRow {
        InkRow(glyph: mark(e.status), title: spokenText(e.name),
               detail: e.status == .active && !view.studying.isEmpty
                   ? spokenText(view.studying.joined(separator: UIText.shared.string("ui.body.list_sep"))) : nil,
               value: Text(verbatim: "\(e.points)/\(e.totalPoints)"), selected: e.status == .active)
    }

    private func mark(_ s: ResearchQueries.Status) -> String {
        switch s {
        case .locked: "・"
        case .available: "○"
        case .active: "◎"
        case .done: "●"
        }
    }
}

enum BuildRowKind: Equatable {
    case button
    case plain

    static func of(_ option: BaseView.BuildOption) -> Self {
        option.affordable ? .button : .plain
    }
}
