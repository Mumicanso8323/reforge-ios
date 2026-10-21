import SwiftUI
import ReForgeEngine

/// 設計・ノートの要素の解放の ID(本体の UIElements。条件はコンテンツの uiGates。表に無い ID は出す)。
enum BenchGate {
    static let sheet = UIElements.designSheet
    static let trial = UIElements.designTrial
    static let plate = UIElements.designPlate
    static let hints = UIElements.designHints
    static let trials = UIElements.notesTrials
    static let codex = UIElements.notesCodex
    static let clues = UIElements.notesClues
    static let documents = UIElements.notesDocuments
}

extension GameStore {
    /// 画面の要素を出してよいか(Frame.ui)。
    func benchOpen(_ id: UIElementID) -> Bool { ui.isOpen(id) }
}

/// 設計のタブ: 縦の工程表で並びを組み、試し、札にする。手がかりと所見もここから見られる。担当: U17。
/// シートもダイアログも出さない(断られた理由はタブの中に 1 行)。時計は止めない。
struct DesignTabView: View {
    @Bindable var app: AppModel
    let store: GameStore
    @State private var showClues = false
    @State private var removedStep: RemovedStep?
    @State private var removeUndoTask: Task<Void, Never>?

    private struct RemovedStep {
        let step: ProcessStep
        let index: Int
        var seconds: Int
    }

    private var wb: WorkbenchModel { store.workbench }

    var body: some View {
        InkPanel(title: ui("ui.tab.design")) {
            if let m = wb.message {
                spokenText(m).foregroundStyle(InkColor.notice).accessibilityIdentifier("benchMessage")
            }
            if let removedStep {
                UndoBand(label: UIText.shared.string("ui.button.clear"), seconds: removedStep.seconds, undo: undoRemove)
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
            ui("ui.body.trial_input").foregroundStyle(InkColor.textDim)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array((wb.bench?.materials ?? []).enumerated()), id: \.offset) { _, s in
                        chip(spokenText("\(s.name) ×\(s.quantity)"), sense: s.percent,
                             on: wb.input == s.selector) {
                            Task { await wb.choose(input: s.selector, store) }
                        }
                    }
                }
            }
            if store.benchOpen(BenchGate.trial) {
                HStack(spacing: 10) {
                    ui("ui.body.quantity")
                    chip(Text(verbatim: "−"), on: false) { wb.quantity = max(1, wb.quantity - 1) }
                    Text(verbatim: "\(wb.quantity)").frame(minWidth: 24).accessibilityIdentifier("quantity")
                    chip(Text(verbatim: "+"), on: false) { wb.quantity = min(99, wb.quantity + 1) }
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
                removeStep: { i in remove(i) }))
                .padding(10)
                .background(InkColor.panel)
        } else {
            ui("ui.body.pick_module").foregroundStyle(InkColor.textDim)
        }
    }

    private var modulePalette: some View {
        VStack(alignment: .leading, spacing: 6) {
            ui("ui.body.module_label").foregroundStyle(InkColor.textDim)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(wb.bench?.modules ?? [], id: \.module) { m in
                    chip(spokenText("\(m.glyph) \(m.name)"), note: m.missing, on: false, dim: m.missing != nil) {
                        Task { await wb.append(m.module, store) }
                    }
                    .accessibilityIdentifier("module.\(m.module.rawValue)")
                }
                // まだ知らない段があることだけを見せる(名前は出さない)
                if let n = wb.bench?.unknownModules, n > 0 {
                    ui("ui.body.unknown_modules", ["n": .int(n)])
                        .foregroundStyle(InkColor.textFaint)
                        .frame(minHeight: InkMetric.buttonHeight)
                        .accessibilityIdentifier("unknownModules")
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
                ui("ui.body.additive_target", ["n": .int(target + 1)]).foregroundStyle(InkColor.textDim)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(adds.enumerated()), id: \.offset) { _, s in
                            if case .item(let item) = s.selector.stuff {
                                chip(spokenText("\(s.name) ×\(s.quantity)"), on: inStep.contains(item)) {
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
                bigButton(ui("ui.button.trial"), id: "trialButton", kind: .primary, enabled: !wb.steps.isEmpty && wb.input != nil) {
                    Task { await wb.trial(store) }
                }
            }
            if store.benchOpen(BenchGate.plate) {
                bigButton(ui("ui.button.make_plate"), id: "plateButton", enabled: !wb.steps.isEmpty) {
                    Task { await wb.makePlate(store) }
                }
            }
            bigButton(ui("ui.button.clear"), id: "clearButton", enabled: !wb.steps.isEmpty) { Task { await wb.clear(store) } }
        }
    }

    // MARK: 札

    private func platesArea(_ plates: [DesignBench.Plate]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ui("ui.body.plates").foregroundStyle(InkColor.textDim)
            ForEach(plates, id: \.design) { p in
                HStack(spacing: 8) {
                    InkRow(glyph: "▤", title: spokenText(p.result ?? UIText.shared.string("ui.body.unknown")),
                           detail: spokenText(p.steps.joined(separator: " → ")))
                    chip(ui("ui.button.load_plate"), on: false) { Task { await wb.load(plate: p, store) } }
                    chip(ui("ui.button.discard_plate"), on: false) { Task { await wb.discard(p, store) } }
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
                    HStack(spacing: 6) {
                        ui("ui.body.clues_toggle", ["clues": .int(nb.clues.count), "findings": .int(nb.findings.count)])
                        Text(verbatim: showClues ? "▾" : "▸")
                    }
                        .foregroundStyle(InkColor.textDim)
                        .frame(minHeight: InkMetric.buttonHeight, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("cluesToggle")
                if showClues {
                    ForEach(Array(nb.clues.enumerated()), id: \.offset) { _, c in ClueLineView(clue: c) }
                    ForEach(Array(nb.findings.enumerated()), id: \.offset) { _, f in
                        ui("ui.body.finding_line", ["text": .string(f.text)]).font(InkFont.small)
                    }
                }
            }
        }
    }

    // MARK: 部品

    /// 小さな選択(Theme の secondary。選んでいる物は錆の印 ▸ を付ける。primary は「試す」だけ)。
    private func chip(_ label: Text, sense: Int? = nil, note: String? = nil, on: Bool, dim: Bool = false,
                      _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if on { Text(verbatim: "▸") }
                    label
                }
                .foregroundStyle(on ? InkColor.accent : (dim ? InkColor.textDim : InkColor.text))
                if let sense {
                    HStack(spacing: 4) {
                        ui("ui.body.sense_label")
                        SenseWords.phrase(sense)
                    }
                    .font(InkFont.caption).foregroundStyle(InkColor.textDim).lineLimit(1)
                }
                if let note { spokenText(note).font(InkFont.caption).foregroundStyle(InkColor.textDim).lineLimit(1) }
            }
        }
        .buttonStyle(.ink(.secondary, fill: false))
    }

    @ViewBuilder private func bigButton(_ label: Text, id: String, kind: InkButtonKind = .secondary, enabled: Bool,
                                        _ action: @escaping () -> Void) -> some View {
        if enabled {
            Button(action: action) { label }
                .buttonStyle(.ink(kind))
                .accessibilityIdentifier(id)
        }
    }

    private func remove(_ index: Int) {
        guard wb.steps.indices.contains(index) else { return }
        let removed = wb.steps[index]
        removeUndoTask?.cancel()
        Task {
            await wb.remove(index, store)
            removedStep = RemovedStep(step: removed, index: index, seconds: 4)
            removeUndoTask = Task { @MainActor in
                for seconds in stride(from: 3, through: 0, by: -1) {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard !Task.isCancelled else { return }
                    removedStep?.seconds = seconds
                }
                removedStep = nil
            }
        }
    }

    private func undoRemove() {
        guard let removedStep else { return }
        removeUndoTask?.cancel()
        removeUndoTask = nil
        self.removedStep = nil
        Task { await wb.restore(step: removedStep.step, at: removedStep.index, store) }
    }
}

/// 手がかりの 1 行(何について・本文・出典の語)。
struct ClueLineView: View {
    let clue: NotebookPage.Clue

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ui("ui.body.quote", ["text": .string(clue.text)])
            ui("ui.body.clue_meta", ["source": .string(clue.source), "about": .string(clue.about), "day": .int(clue.day)])
                .font(InkFont.small).foregroundStyle(InkColor.textDim)
        }
    }
}
