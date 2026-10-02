import SwiftUI
import ReForgeEngine

/// 設計・ノートの要素の解放の ID(U18 の UIGateDef で条件を書く。表に無い ID は出す)。
enum BenchGate {
    static let sheet = "design.sheet"
    static let trial = "design.trial"
    static let plate = "design.plate"
    static let hints = "design.hints"
    static let trials = "notes.trials"
    static let codex = "notes.codex"
    static let clues = "notes.clues"
    static let documents = "notes.documents"
}

extension GameStore {
    /// 画面の要素を出してよいか。U18 の `Frame.ui`(UIUnlocks)が統合に入ったら、その isOpen に差し替える。
    func benchOpen(_ id: String) -> Bool { true }
}

/// 設計のタブ: 縦の工程表で並びを組み、試し、札にする。手がかりと所見もここから見られる。担当: U17。
/// シートもダイアログも出さない(断られた理由はタブの中に 1 行)。時計は止めない。
struct DesignTabView: View {
    @Bindable var app: AppModel
    let store: GameStore
    @State private var showClues = false

    private var wb: WorkbenchModel { store.workbench }

    var body: some View {
        InkPanel(title: Text("設計")) {
            if let m = wb.message {
                Text(verbatim: m).foregroundStyle(InkColor.notice).accessibilityIdentifier("benchMessage")
            }
            if store.benchOpen(BenchGate.sheet) {
                inputRow
                sheetArea
                modulePalette
                additiveRow
                actionRow
            }
            if let t = wb.lastTrial { ProcessSheetView(sheet: t) }
            if store.benchOpen(BenchGate.plate), let plates = wb.bench?.plates, !plates.isEmpty {
                platesArea(plates)
            }
            if store.benchOpen(BenchGate.hints) { cluesArea }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // 在庫・ノート・知識が変わったとき、日が変わったときに引き直す(Frame.benchRevision)
        .task(id: store.benchRevision) { await wb.reload(store) }
        .accessibilityIdentifier("designTab")
    }

    // MARK: 試す物

    private var inputRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: "── 試す物").foregroundStyle(InkColor.textDim)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array((wb.bench?.materials ?? []).enumerated()), id: \.offset) { _, s in
                        chip("\(s.name) ×\(s.quantity)", sub: s.percent.map { "手: \(SenseWords.phrase($0))" },
                             on: wb.input == s.selector) {
                            Task { await wb.choose(input: s.selector, store) }
                        }
                    }
                }
            }
            if store.benchOpen(BenchGate.trial) {
                HStack(spacing: 10) {
                    Text(verbatim: "数")
                    chip("−", on: false) { wb.quantity = max(1, wb.quantity - 1) }
                    Text(verbatim: "\(wb.quantity)").frame(minWidth: 24).accessibilityIdentifier("quantity")
                    chip("+", on: false) { wb.quantity = min(99, wb.quantity + 1) }
                }
            }
        }
    }

    // MARK: 工程表

    @ViewBuilder
    private var sheetArea: some View {
        if let d = wb.draft {
            ProcessSheetView(sheet: d, actions: ProcessSheetActions(
                selectStep: { i in wb.selectedStep = i },
                selectedStep: wb.selectedStep,
                moveStep: { i, d in Task { await wb.move(i, by: d, store) } },
                removeStep: { i in Task { await wb.remove(i, store) } }))
                .padding(10)
                .background(InkColor.panel)
        } else {
            Text(verbatim: "  │\n  │ 下の段を選んで積む\n  │").foregroundStyle(InkColor.textDim)
        }
    }

    private var modulePalette: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: "── 段").foregroundStyle(InkColor.textDim)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(wb.bench?.modules ?? [], id: \.module) { m in
                    chip("\(m.glyph) \(m.name)", sub: m.missing, on: false, dim: m.missing != nil) {
                        Task { await wb.append(m.module, store) }
                    }
                    .accessibilityIdentifier("module.\(m.module.rawValue)")
                }
            }
        }
    }

    @ViewBuilder
    private var additiveRow: some View {
        if !wb.steps.isEmpty, let adds = wb.bench?.additives, !adds.isEmpty {
            let target = wb.selectedStep ?? wb.steps.count - 1
            let inStep = Set(wb.steps.indices.contains(target) ? wb.steps[target].inputItems : [])
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: "── \(target + 1). の段に入れる").foregroundStyle(InkColor.textDim)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(adds.enumerated()), id: \.offset) { _, s in
                            if case .item(let item) = s.selector.stuff {
                                chip("\(s.name) ×\(s.quantity)", on: inStep.contains(item)) {
                                    Task { await wb.toggleAdditive(item, store) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            if store.benchOpen(BenchGate.trial) {
                bigButton("試す", id: "trialButton", kind: .primary, enabled: !wb.steps.isEmpty && wb.input != nil) {
                    Task { await wb.trial(store) }
                }
            }
            if store.benchOpen(BenchGate.plate) {
                bigButton("札にする", id: "plateButton", enabled: !wb.steps.isEmpty) {
                    Task { await wb.makePlate(store) }
                }
            }
            bigButton("崩す", id: "clearButton", enabled: !wb.steps.isEmpty) { Task { await wb.clear(store) } }
        }
    }

    // MARK: 札

    private func platesArea(_ plates: [DesignBench.Plate]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: "── 札").foregroundStyle(InkColor.textDim)
            ForEach(plates, id: \.design) { p in
                HStack(spacing: 8) {
                    InkRow(glyph: "▤", title: Text(verbatim: p.result ?? "？"),
                           detail: Text(verbatim: p.steps.joined(separator: " → ")))
                    chip("写す", on: false) { Task { await wb.load(plate: p, store) } }
                    chip("捨てる", on: false) { Task { await wb.discard(p, store) } }
                }
            }
        }
    }

    // MARK: 手がかり(推理の材料。ノートと同じものを、組みながら見られるように)

    @ViewBuilder
    private var cluesArea: some View {
        if let nb = wb.notebook, !(nb.clues.isEmpty && nb.findings.isEmpty) {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    showClues.toggle()
                } label: {
                    Text(verbatim: "── 手がかり \(nb.clues.count) ・所見 \(nb.findings.count) \(showClues ? "▾" : "▸")")
                        .foregroundStyle(InkColor.textDim)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("cluesToggle")
                if showClues {
                    ForEach(Array(nb.clues.enumerated()), id: \.offset) { _, c in ClueLineView(clue: c) }
                    ForEach(Array(nb.findings.enumerated()), id: \.offset) { _, f in
                        Text(verbatim: "・\(f.text)").font(InkFont.small)
                    }
                }
            }
        }
    }

    // MARK: 部品

    /// 小さな選択(Theme の secondary。選んでいる物は錆の印 ▸ を付ける。primary は「試す」だけ)。
    private func chip(_ label: String, sub: String? = nil, on: Bool, dim: Bool = false,
                      _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: (on ? "▸ " : "") + label)
                    .foregroundStyle(on ? InkColor.accent : (dim ? InkColor.textDim : InkColor.text))
                if let sub { Text(verbatim: sub).font(InkFont.caption).foregroundStyle(InkColor.textDim).lineLimit(1) }
            }
        }
        .buttonStyle(.ink(.secondary, fill: false))
    }

    private func bigButton(_ label: String, id: String, kind: InkButtonKind = .secondary, enabled: Bool,
                           _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(verbatim: label) }
            .buttonStyle(.ink(kind))
            .disabled(!enabled)
            .accessibilityIdentifier(id)
    }
}

/// 手がかりの 1 行(何について・本文・出典の語)。
struct ClueLineView: View {
    let clue: NotebookPage.Clue

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "「\(clue.text)」")
            Text(verbatim: "  ── \(clue.source)・\(clue.about)・\(clue.day)日目")
                .font(InkFont.small).foregroundStyle(InkColor.textDim)
        }
    }
}
