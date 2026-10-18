import SwiftUI
import ReForgeEngine

/// ノートのタブ: 試したこと・所見・素材の図鑑・手がかり(出典つき)・記録(工程表で開く)・資料。担当: U17。
/// 頁はシートにせず、タブの中で開いて「もどる」で閉じる。資料を読むのは任意で、時計は止めない。
struct NotesTabView: View {
    @Bindable var app: AppModel
    let store: GameStore

    private var wb: WorkbenchModel { store.workbench }

    var body: some View {
        InkPanel(title: wb.page == .index ? ui("ui.tab.notes") : nil) {
            if let m = wb.message {
                spokenText(m).foregroundStyle(InkColor.notice)
            }
            switch wb.page {
            case .index: index
            case .sheet(let s): sheetPage(s)
            case .document: documentPage
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // 在庫・ノート・知識が変わったとき、日が変わったときに引き直す(Frame.benchRevision)
        .task(id: store.benchRevision) { await wb.reload(store) }
        .accessibilityIdentifier("notesTab")
    }

    // MARK: 目次

    @ViewBuilder
    private var index: some View {
        if let nb = wb.notebook {
            if store.benchOpen(BenchGate.trials), !nb.trials.isEmpty {
                section(ui("ui.body.section_trials"))
                ForEach(nb.trials, id: \.record) { t in
                    row {
                        VStack(alignment: .leading, spacing: 2) {
                            spokenText("\(t.input.name) → \(t.result.name)")
                            HStack(spacing: 4) {
                                ui("ui.body.trial_meta", ["day": .int(t.day), "steps": .int(t.steps), "quantity": .int(t.quantity)])
                                SenseWords.phrase(t.result.percent)
                            }
                                .font(InkFont.small).foregroundStyle(InkColor.textDim)
                        }
                    } open: { Task { await wb.open(.sheet(.trial(t.record)), store) } }
                }
                if !nb.findings.isEmpty {
                    section(ui("ui.body.section_findings"))
                    ForEach(Array(nb.findings.enumerated()), id: \.offset) { _, f in
                        row { ui("ui.body.finding_line", ["text": .string(f.text)]) } open: {
                            Task { await wb.open(.sheet(.trial(f.trial)), store) }
                        }
                    }
                }
            }
            if store.benchOpen(BenchGate.codex), !nb.codex.isEmpty {
                section(ui("ui.body.section_codex"))
                ForEach(Array(nb.codex.enumerated()), id: \.offset) { _, c in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(verbatim: c.item ? (c.made ? "◆" : "◇") : (c.made ? "■" : "□")).foregroundStyle(c.made ? InkColor.accent : InkColor.textDim)
                            spokenText(c.name).foregroundStyle(c.made ? InkColor.text : InkColor.textDim)
                            Spacer()
                            if let p = c.percent {
                                SenseWords.phrase(p).font(InkFont.small).foregroundStyle(InkColor.textDim)
                            }
                        }
                        ForEach(c.clues, id: \.self) { t in
                            ui("ui.body.quote", ["text": .string(t)]).font(InkFont.small).foregroundStyle(InkColor.textDim)
                        }
                    }
                }
            }
            if store.benchOpen(BenchGate.clues), !nb.clues.isEmpty {
                section(ui("ui.body.section_clues"))
                ForEach(Array(nb.clues.enumerated()), id: \.offset) { _, c in ClueLineView(clue: c) }
            }
            if !nb.records.isEmpty {
                section(ui("ui.body.records"))
                ForEach(nb.records, id: \.sheet) { r in
                    row { spokenText("▤ \(r.title)") } open: {
                        Task { await wb.open(.sheet(.record(r.sheet)), store) }
                    }
                }
            }
            if store.benchOpen(BenchGate.documents), !nb.documents.isEmpty {
                section(ui("ui.body.section_documents"))
                ForEach(nb.documents, id: \.id) { d in
                    row {
                        HStack {
                            spokenText("≡ \(d.title)")
                            Spacer()
                            if let s = d.source { spokenText(s).font(InkFont.small).foregroundStyle(InkColor.textDim) }
                        }
                    } open: { Task { await wb.open(.document(d.id), store) } }
                }
            }
            if nb.trials.isEmpty && nb.codex.isEmpty && nb.clues.isEmpty && nb.records.isEmpty && nb.documents.isEmpty {
                ui("ui.body.notes_empty").foregroundStyle(InkColor.textDim)
            }
        }
    }

    // MARK: 頁

    @ViewBuilder
    private func sheetPage(_ source: ProcessSheet.Source) -> some View {
        backRow
        if let s = wb.openSheet {
            ProcessSheetView(sheet: s, actions: actions(for: source))
            if let a = wb.answering, let sid = sheetID(source) {
                VStack(alignment: .leading, spacing: 4) {
                    ui("ui.body.answer_records").foregroundStyle(InkColor.textDim)
                    if a.candidates.isEmpty { ui("ui.body.answer_none").foregroundStyle(InkColor.textDim) }
                    ForEach(a.candidates, id: \.record) { c in
                        row { spokenText(c.label) } open: { Task { await wb.place(c, sheet: sid, store) } }
                    }
                }
                .padding(8)
                .background(InkColor.panel)
            }
            if let im = s.grant, let sid = sheetID(source) { grantArea(im, labels: s.labels, sheet: sid) }
            if s.rosterConfirmed == false, let sid = sheetID(source) {
                let labels = s.labels
                InkHoldButton(label: coreText(labels?.rosterConfirm, ui("ui.roster.confirm")), hint: coreText(labels?.rosterConfirmHint, ui("ui.roster.confirm_hint"))) {
                    Task { await wb.confirmRoster(sheet: sid, store) }
                }
                .accessibilityIdentifier("confirmRoster")
            }
        }
    }

    /// 人ごとに付けられる技能と、その選択肢。
    /// 内容の層が名前を渡したらそれ、無ければ文言の表の文(いまの言語)。
    private func coreText(_ text: String?, _ fallback: Text) -> Text {
        text.map { spokenText($0) } ?? fallback
    }

    private func grantArea(_ im: ProcessSheet.SkillGrant, labels: ProcessSheet.Labels?, sheet sid: SheetID) -> some View {
        InkSection(title: coreText(labels?.grantTitle, ui("ui.grant.title"))) {
            ForEach(im.targets, id: \.person) { t in
                VStack(alignment: .leading, spacing: 6) {
                    InkRow(title: spokenText(t.name),
                           detail: t.written.isEmpty ? nil : spokenText(t.written.formatted(.list(type: .and))),
                           value: t.declined == nil ? nil : (t.declined == true ? coreText(labels?.grantRefused, ui("ui.grant.refused")) : coreText(labels?.grantSkip, ui("ui.grant.skip"))))
                    if t.declined == nil {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(im.skills, id: \.id) { k in
                                    Button { Task { await wb.grant(sheet: sid, person: t.person, skill: k.id, store) } }
                                        label: { spokenText(k.name) }
                                        .buttonStyle(.ink(.secondary, fill: false))
                                }
                                Button { Task { await wb.grant(sheet: sid, person: t.person, skill: nil, store) } }
                                    label: { coreText(labels?.grantSkip, ui("ui.grant.skip")) }
                                    .buttonStyle(.ink(.quiet, fill: false))
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var documentPage: some View {
        backRow
        if let d = wb.openDocument {
            spokenText(d.title).font(InkFont.heading).bold()
            if let s = d.source { spokenText("── \(s)").foregroundStyle(InkColor.textDim) }
            spokenText(d.body).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("documentBody")
        }
    }

    private var backRow: some View {
        Button {
            Task { await wb.back(store) }
        } label: {
            ui("ui.button.back")
        }
        .buttonStyle(.ink(.quiet, fill: false))
        .accessibilityIdentifier("notesBack")
    }

    private func sheetID(_ s: ProcessSheet.Source) -> SheetID? {
        switch s {
        case .record(let sid), .recordEntry(let sid, _): sid
        case .design, .trial, .draft: nil
        }
    }

    private func actions(for source: ProcessSheet.Source) -> ProcessSheetActions {
        guard let sid = sheetID(source) else { return ProcessSheetActions() }
        var a = ProcessSheetActions()
        if case .record = source {
            a.openEntry = { slot in Task { await wb.open(.sheet(.recordEntry(sid, slot: slot)), store) } }
            if wb.openSheet?.rosterConfirmed != true {
                a.setRosterPick = { p, on in Task { await wb.board(sheet: sid, person: p, included: on, store) } }
            }
        }
        a.placeAnswer = { row in Task { await wb.beginAnswer(sheet: sid, row: row, store) } }
        return a
    }

    // MARK: 部品

    private func section(_ title: Text) -> some View {
        title.font(InkFont.small).foregroundStyle(InkColor.textDim).padding(.top, 8)
    }

    private func row<C: View>(@ViewBuilder _ content: () -> C, open: @escaping () -> Void) -> some View {
        Button(action: open) {
            content()
                .frame(maxWidth: .infinity, minHeight: InkMetric.rowHeight, alignment: .leading)
                .overlay(alignment: .bottom) { Rectangle().fill(InkColor.rule.opacity(0.6)).frame(height: InkMetric.rule) }
                .contentShape(Rectangle())
        }
        .buttonStyle(.inkRow)
    }
}
