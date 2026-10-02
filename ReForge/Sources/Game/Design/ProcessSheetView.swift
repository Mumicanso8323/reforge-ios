import SwiftUI
import ReForgeEngine

/// 工程表の操作(どれも nil なら、その操作の印を出さない)。
/// プレイヤーの下書き・試作・ライン札・コンテンツの記録で同じ部品を使う(REQ-S8)。
struct ProcessSheetActions {
    /// 段を選ぶ(段に入れる物の行き先)。
    var selectStep: ((Int) -> Void)?
    var selectedStep: Int?
    /// 段を上下に動かす(段の番号, -1 / +1)。
    var moveStep: ((Int, Int) -> Void)?
    var removeStep: ((Int) -> Void)?
    /// 記録の並びの 1 件(席の番号)を開く。空いた席も開ける。
    var openEntry: ((Int) -> Void)?
    /// 答えを置ける行(answerRow)に答えを置く。
    var placeAnswer: ((String) -> Void)?
    /// 名簿で「乗る / 残る」を決める。
    var setBoarding: ((PersonID, Bool) -> Void)?
}

/// 縦一列の工程表。頭(入力と見当)→ 段(見込み・所見)→ 結果(と試作の結果カード)。
struct ProcessSheetView: View {
    let sheet: ProcessSheet
    var actions = ProcessSheetActions()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: sheet.title).font(InkFont.heading).bold()
                Spacer()
                if let t = sheet.tally {
                    Text(verbatim: "\(t.filled) / \(t.slots)").foregroundStyle(InkColor.textDim)
                }
            }
            if let h = sheet.head {
                Text(verbatim: "\(h.name) ── 手: \(SenseWords.phrase(h.percent))")
                    .foregroundStyle(InkColor.accent)
                connector
            }
            ForEach(Array(sheet.rows.enumerated()), id: \.offset) { i, row in
                rowView(row, last: i == sheet.rows.count - 1)
            }
            if let r = sheet.result {
                Text(verbatim: "═ \(r)").bold().foregroundStyle(InkColor.accent)
                    .accessibilityIdentifier("sheetResult")
            }
            if let c = sheet.card { TrialCardView(card: c) }
        }
        .font(InkFont.body)
        .foregroundStyle(InkColor.text)
        .accessibilityIdentifier("processSheet")
    }

    private var connector: some View {
        Text(verbatim: "  │").foregroundStyle(InkColor.textDim)
    }

    @ViewBuilder
    private func rowView(_ row: ProcessSheet.Row, last: Bool) -> some View {
        let selected = row.step != nil && row.step == actions.selectedStep
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(verbatim: lead(row)).foregroundStyle(selected ? InkColor.accent : InkColor.textDim)
                Text(verbatim: row.title)
                    .foregroundStyle(row.empty ? InkColor.textDim : InkColor.text)
                    .bold(selected)
                if let n = row.note { Text(verbatim: "+ \(n)").foregroundStyle(InkColor.textDim).lineLimit(1) }
                if let f = row.figure { Text(verbatim: "\(f)").foregroundStyle(InkColor.textDim) }
                Spacer(minLength: 4)
                controls(row)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if let s = row.step { actions.selectStep?(s) }
                if let slot = row.slot { actions.openEntry?(slot) }
            }
            if let f = row.forecast {
                Text(verbatim: "  │ → \(f.name)(\(SenseWords.phrase(f.percent)))").foregroundStyle(InkColor.textDim)
            } else if row.step != nil {
                Text(verbatim: "  │ → ？").foregroundStyle(InkColor.textDim)
            }
            ForEach(row.findings, id: \.self) { t in
                Text(verbatim: "  │ ・\(t)").font(InkFont.small).foregroundStyle(InkColor.textDim)
            }
            if let a = row.answer {
                Text(verbatim: "  └ \(a)").foregroundStyle(InkColor.accent)
            }
        }
    }

    private func lead(_ row: ProcessSheet.Row) -> String {
        if let s = row.slot { return String(format: "%02d", s) }
        if let s = row.step { return "\(s + 1)." }
        return "・"
    }

    @ViewBuilder
    private func controls(_ row: ProcessSheet.Row) -> some View {
        if let s = row.step {
            if let move = actions.moveStep {
                glyphButton("▲", id: "up\(s)") { move(s, -1) }
                glyphButton("▼", id: "down\(s)") { move(s, 1) }
            }
            if let remove = actions.removeStep { glyphButton("✕", id: "remove\(s)") { remove(s) } }
        }
        if let id = row.answerRow, let place = actions.placeAnswer {
            glyphButton(row.answer == nil ? "置く" : "置き直す", id: "answer.\(id)") { place(id) }
        }
        if let p = row.person, row.aboard != nil || row.declared != nil, let set = actions.setBoarding {
            if row.declared != nil { Text(verbatim: "言").font(InkFont.small).foregroundStyle(InkColor.textDim) }
            glyphButton(row.aboard == true ? "[乗る]" : " 乗る ", id: "aboard.\(p.rawValue)") { set(p, true) }
            glyphButton(row.aboard == false ? "[残る]" : " 残る ", id: "stay.\(p.rawValue)") { set(p, false) }
        }
    }

    private func glyphButton(_ label: String, id: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: label).frame(minWidth: 32, minHeight: 32)
        }
        .buttonStyle(.plain)
        .foregroundStyle(InkColor.accent)
        .accessibilityIdentifier(id)
    }
}

/// 試作の結果カード。
struct TrialCardView: View {
    let card: ProcessSheet.Card

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: "┌ \(card.product.name) ×\(card.quantity)\(card.unique ? " ★" : "")").bold()
            Text(verbatim: "│ 手: \(SenseWords.phrase(card.product.percent))  硬さ \(card.hardness)  粘り \(card.toughness)")
            if !card.byproducts.isEmpty {
                Text(verbatim: "│ ほかに: \(card.byproducts.joined(separator: "・"))")
            }
            ForEach(card.findings, id: \.self) { f in Text(verbatim: "│ ・\(f)") }
            if !card.used.isEmpty {
                Text(verbatim: "└ 使った: " + card.used.map { "\($0.name) \($0.quantity)" }.joined(separator: "・"))
                    .foregroundStyle(InkColor.textDim)
            }
        }
        .font(InkFont.small)
        .padding(8)
        .background(InkColor.panel)
        .accessibilityIdentifier("trialCard")
    }
}
