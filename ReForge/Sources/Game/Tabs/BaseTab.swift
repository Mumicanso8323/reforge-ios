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
    @State private var points: [SavePoint] = []

    var body: some View {
        InkPanel(title: Text("拠点")) {
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
                Button { Task { await app.backToTitle() } } label: { Text("タイトルへ") }
                    .buttonStyle(.ink(.quiet))
            }
        }
        .task(id: store.revision) {
            base = await store.host.base()
            research = await store.host.research()
            points = store.savePoints()
        }
        .accessibilityIdentifier("baseTab")
        #if DEBUG
        .modifier(ResearchSectionScrollModifier(researchLoaded: research != nil))
        #endif
    }

    private func stock(_ v: BaseView) -> some View {
        InkSection(title: Text("蓄え")) {
            if v.stock.isEmpty {
                InkRow(title: Text("なにもない")).foregroundStyle(InkColor.textDim)
            }
            ForEach(v.stock, id: \.name) { s in
                InkRow(title: Text(verbatim: s.name), value: Text(verbatim: "\(s.quantity)"))
            }
        }
    }

    private func built(_ v: BaseView) -> some View {
        InkSection(title: Text("建てた物")) {
            ForEach(v.built, id: \.id) { b in
                InkRow(glyph: b.glyph, title: Text(verbatim: b.name), detail: detail(b), value: state(b.state))
            }
        }
    }

    private func detail(_ b: BaseView.Built) -> Text? {
        b.workers.isEmpty ? nil : Text(verbatim: b.workers.joined(separator: "・"))
    }

    private func state(_ s: BaseView.Built.State) -> Text {
        switch s {
        case .running: Text("動いている")
        case .building(let p): Text("建造中 \(p / 10)%")
        case .stopped(let r): Text(verbatim: r)
        case .broken: Text("壊れている")
        }
    }

    /// 建てる: 選ぶと地図に戻り、次にタップしたマスに建てる(確認は出さない。片付ければ材料は戻る)。
    private func build(_ v: BaseView) -> some View {
        InkSection(title: Text("建てる")) {
            ForEach(v.buildable, id: \.kind) { o in
                switch BuildRowKind.of(o) {
                case .button:
                    Button {
                        store.beginPlacing(o.kind)
                    } label: {
                        InkRow(glyph: o.glyph, title: Text(verbatim: o.name),
                               detail: Text(verbatim: o.cost.map { "\($0.name)×\($0.quantity)" }.joined(separator: " ")),
                               selected: store.placing == o.kind)
                    }
                    .buttonStyle(.inkRow)
                    .accessibilityIdentifier("build-\(o.kind.rawValue)")
                case .plain:
                    InkRow(glyph: o.glyph, title: Text(verbatim: o.name), detail: missing(o))
                        .foregroundStyle(InkColor.textDim)
                        .accessibilityValue("足りない")
                }
            }
            let unknownCount = v.unknownStructures + v.shadows.count
            if unknownCount > 0 {
                InkRow(title: Text("まだ作り方を知らない物 \(unknownCount) 件"))
                    .foregroundStyle(InkColor.textDim)
                    .accessibilityIdentifier("buildUnknown")
            }
        }
    }

    private func missing(_ option: BaseView.BuildOption) -> Text {
        option.missing.enumerated().reduce(Text(verbatim: "")) { text, item in
            let part = Text("あと \(item.element.name)×\(item.element.quantity)") // xcstrings: @,lld
            return item.offset == 0 ? part : text + Text(verbatim: " ") + part
        }
    }

    private func lines(_ v: BaseView) -> some View {
        InkSection(title: Text("運搬")) {
            ForEach(v.lines, id: \.id) { l in
                InkRow(glyph: "→", title: Text(verbatim: "\(l.from) → \(l.to)"),
                       detail: l.blocked.map { Text(verbatim: $0) }
                           ?? (l.haulers.isEmpty ? nil : Text(verbatim: l.haulers.joined(separator: "・"))),
                       value: Text("昨日 \(l.movedYesterday)"))
            }
        }
    }

    /// 手動セーブ(3 枠。確認なしで上書き)とロード(夜明け・手動)。
    private var saves: some View {
        InkSection(title: Text("記録")) {
            ForEach(0..<SavePolicy.manualSlots, id: \.self) { i in
                let existing = points.first { $0.slot == .manual(index: i) }?.summary
                HStack(spacing: InkMetric.gap) {
                    InkRow(title: slotText(.manual(index: i)),
                           value: existing.map { Text("\($0.day) 日目") } ?? Text("空き"))
                    Button {
                        Task {
                            await store.saveManual(i)
                            points = store.savePoints()
                        }
                    } label: { Text("書く") }
                        .buttonStyle(.ink(.secondary, fill: false))
                        .accessibilityIdentifier("save-\(i)")
                }
            }
            ForEach(points.filter { $0.summary?.active == true }, id: \.slot) { p in
                Button {
                    Task { await store.load(p.slot) }
                } label: {
                    InkRow(title: slotText(p.slot), value: Text("読む"))
                }
                .buttonStyle(.inkRow)
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
        InkSection(title: Text("研究")) {
            if !view.hasDesk {
                InkRow(title: Text("研究机がない")).foregroundStyle(InkColor.textDim)
            }
            ForEach(view.entries, id: \.id) { e in
                Button { store.send(e.selectCommand) } label: {
                    InkRow(glyph: mark(e.status), title: Text(verbatim: e.name),
                           detail: e.status == .active && !view.studying.isEmpty
                               ? Text(verbatim: view.studying.joined(separator: "・")) : nil,
                           value: Text(verbatim: "\(e.points)/\(e.totalPoints)"), selected: e.status == .active)
                }
                .buttonStyle(.inkRow)
                .disabled(e.status == .locked || e.status == .done)
                .accessibilityIdentifier("research-\(e.id.rawValue)")
            }
            if view.hiddenCount > 0 {
                // 深さの気配: 名前は出さず、数だけ(§10 HNT-16)
                InkRow(title: Text("この先にまだ \(view.hiddenCount) 件"))
                    .foregroundStyle(InkColor.textDim)
                    .accessibilityIdentifier("researchHidden")
            }
        }
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
