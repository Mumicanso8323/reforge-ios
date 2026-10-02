import SwiftUI
import ReForgeEngine

/// ノートのタブ: 試したこと・所見・素材の図鑑・手がかり(出典つき)・記録(工程表で開く)・資料。担当: U17。
/// 頁はシートにせず、タブの中で開いて「もどる」で閉じる。資料を読むのは任意で、時計は止めない。
struct NotesTabView: View {
    @Bindable var app: AppModel
    let store: GameStore

    private var wb: WorkbenchModel { store.workbench }

    var body: some View {
        InkPanel(title: wb.page == .index ? Text("ノート") : nil) {
            if let m = wb.message {
                Text(verbatim: m).foregroundStyle(InkColor.notice)
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
                section("試したこと")
                ForEach(nb.trials, id: \.record) { t in
                    row {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: "\(t.input.name) → \(t.result.name)")
                            HStack(spacing: 4) {
                                Text("\(t.day)日目・\(t.steps)段・\(t.quantity)個・手:")
                                SenseWords.phrase(t.result.percent)
                            }
                                .font(InkFont.small).foregroundStyle(InkColor.textDim)
                        }
                    } open: { Task { await wb.open(.sheet(.trial(t.record)), store) } }
                }
                if !nb.findings.isEmpty {
                    section("所見")
                    ForEach(Array(nb.findings.enumerated()), id: \.offset) { _, f in
                        row { Text(verbatim: "・\(f.text)") } open: {
                            Task { await wb.open(.sheet(.trial(f.trial)), store) }
                        }
                    }
                }
            }
            if store.benchOpen(BenchGate.codex), !nb.codex.isEmpty {
                section("図鑑")
                ForEach(Array(nb.codex.enumerated()), id: \.offset) { _, c in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(verbatim: c.item ? (c.made ? "◆" : "◇") : (c.made ? "■" : "□")).foregroundStyle(c.made ? InkColor.accent : InkColor.textDim)
                            Text(verbatim: c.name).foregroundStyle(c.made ? InkColor.text : InkColor.textDim)
                            Spacer()
                            if let p = c.percent {
                                SenseWords.phrase(p).font(InkFont.small).foregroundStyle(InkColor.textDim)
                            }
                        }
                        ForEach(c.clues, id: \.self) { t in
                            Text("「\(t)」").font(InkFont.small).foregroundStyle(InkColor.textDim)  // xcstrings: @
                        }
                    }
                }
            }
            if store.benchOpen(BenchGate.clues), !nb.clues.isEmpty {
                section("手がかり")
                ForEach(Array(nb.clues.enumerated()), id: \.offset) { _, c in ClueLineView(clue: c) }
            }
            if !nb.records.isEmpty {
                section("記録")
                ForEach(nb.records, id: \.sheet) { r in
                    row { Text(verbatim: "▤ \(r.title)") } open: {
                        Task { await wb.open(.sheet(.record(r.sheet)), store) }
                    }
                }
            }
            if store.benchOpen(BenchGate.documents), !nb.documents.isEmpty {
                section("資料")
                ForEach(nb.documents, id: \.id) { d in
                    row {
                        HStack {
                            Text(verbatim: "≡ \(d.title)")
                            Spacer()
                            if let s = d.source { Text(verbatim: s).font(InkFont.small).foregroundStyle(InkColor.textDim) }
                        }
                    } open: { Task { await wb.open(.document(d.id), store) } }
                }
            }
            if nb.trials.isEmpty && nb.codex.isEmpty && nb.clues.isEmpty && nb.records.isEmpty && nb.documents.isEmpty {
                Text("まだ何も書いていない。").foregroundStyle(InkColor.textDim)
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
                    Text("置く記録").foregroundStyle(InkColor.textDim)
                    if a.candidates.isEmpty { Text("まだ無い。").foregroundStyle(InkColor.textDim) }
                    ForEach(a.candidates, id: \.record) { c in
                        row { Text(verbatim: c.label) } open: { Task { await wb.place(c, sheet: sid, store) } }
                    }
                }
                .padding(8)
                .background(InkColor.panel)
            }
            if let im = s.grant, let sid = sheetID(source) { grantArea(im, labels: s.labels, sheet: sid) }
            if s.rosterConfirmed == false, let sid = sheetID(source) {
                let labels = s.labels
                InkHoldButton(label: Text(verbatim: labels?.rosterConfirm ?? "確定する"), hint: Text(verbatim: labels?.rosterConfirmHint ?? "長押しで確定")) {
                    Task { await wb.confirmRoster(sheet: sid, store) }
                }
                .accessibilityIdentifier("confirmRoster")
            }
        }
    }

    /// 人ごとに付けられる技能と、その選択肢。
    private func grantArea(_ im: ProcessSheet.SkillGrant, labels: ProcessSheet.Labels?, sheet sid: SheetID) -> some View {
        InkSection(title: Text(verbatim: labels?.grantTitle ?? "技能を付ける")) {
            ForEach(im.targets, id: \.person) { t in
                VStack(alignment: .leading, spacing: 6) {
                    InkRow(title: Text(verbatim: t.name),
                           detail: t.written.isEmpty ? nil : Text(verbatim: t.written.formatted(.list(type: .and))),
                           value: t.declined == nil ? nil : (t.declined == true ? Text(verbatim: labels?.grantRefused ?? "本人が断った") : Text(verbatim: labels?.grantSkip ?? "付けない")))
                    if t.declined == nil {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(im.skills, id: \.id) { k in
                                    Button { Task { await wb.grant(sheet: sid, person: t.person, skill: k.id, store) } }
                                        label: { Text(verbatim: k.name) }
                                        .buttonStyle(.ink(.secondary, fill: false))
                                }
                                Button { Task { await wb.grant(sheet: sid, person: t.person, skill: nil, store) } }
                                    label: { Text(verbatim: labels?.grantSkip ?? "付けない") }
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
            Text(verbatim: d.title).font(InkFont.heading).bold()
            if let s = d.source { Text(verbatim: "── \(s)").foregroundStyle(InkColor.textDim) }
            Text(verbatim: d.body).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("documentBody")
        }
    }

    private var backRow: some View {
        Button {
            Task { await wb.back(store) }
        } label: {
            Text("← もどる")
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

    private func section(_ title: LocalizedStringKey) -> some View {
        Text(title).font(InkFont.small).foregroundStyle(InkColor.textDim).padding(.top, 8)
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
