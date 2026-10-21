import SwiftUI
import ReForgeEngine

/// ゲームオーバーの 4 択(同じ重さで並べる。推奨の順位を付けない。D-save.md §3)。
/// 確認のダイアログも長押しも使わない。実行後は短時間だけ取り消せる。
/// 選べない択は出さない(見せて禁じない。要件 Z1)。巻き戻し・ロードの行き先が複数あれば、その下に並べる(既定は先頭)。
struct GameOverView: View {
    @Bindable var app: AppModel
    let store: GameStore
    @State private var choices: [RecoveryChoice] = []
    @State private var problem: String?
    @State private var working = false
    /// 「セーブから読む」の一覧(自動と手動の 2 つの節)を開いているか。
    @State private var loadListOpen = false
    @State private var groups = SavePointGroups(auto: [], manual: [])

    var body: some View {
        InkPlate(title: ui("ui.body.game_over_title")) {
            ForEach(choices, id: \.option) { c in
                VStack(alignment: .leading, spacing: 4) {
                    row(c)
                    if c.option == .loadSavePoint, c.available, loadListOpen {
                        SavePointSections(groups: groups) { run(.loadSavePoint, $0) }
                    } else if c.option != .loadSavePoint, c.available, c.targets.count > 1 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: InkMetric.gap) {
                                ForEach(c.targets, id: \.self) { t in
                                    Button { run(c.option, t) } label: { SlotLabel(slot: t) }
                                        .buttonStyle(.ink(.quiet, fill: false))
                                }
                            }
                        }
                    }
                }
            }
            if let problem {
                spokenText(problem)
                    .font(InkFont.small)
                    .foregroundStyle(InkColor.notice)
                    .accessibilityIdentifier("recoveryProblem")
            }
        }
        .accessibilityIdentifier("gameOver")
        .task(id: store.revision) {
            choices = await store.recoveryChoices()
            groups = store.savePointGroups(activeOnly: true).readable
        }
    }

    @ViewBuilder private func row(_ c: RecoveryChoice) -> some View {
        switch c.option {
        case .restart:
            recoveryButton(c)
        case .loadSavePoint:
            // 読む枠は一覧から選ぶ(自動と手動。先頭へ黙って読まない)。もう一度押すと一覧を閉じる
            recoveryButton(c) { loadListOpen.toggle() }
        case .rewindWithMemory, .continueWithLoss:
            recoveryButton(c)
        }
    }

    /// 択のボタン。押した時の動きは既定で、その択を先頭の行き先で実行する。
    @ViewBuilder private func recoveryButton(_ choice: RecoveryChoice, action: (() -> Void)? = nil) -> some View {
        if choice.available, !working {
            Button { if let action { action() } else { run(choice.option, choice.targets.first) } } label: {
                RecoveryLabel(option: choice.option)
            }
                .buttonStyle(.ink(.secondary))
                .accessibilityIdentifier("recovery-\(choice.option.rawValue)")
        } else if working {
            // 押した直後(本体の返事待ち)は形を保ち、押せる物には見せない
            RecoveryLabel(option: choice.option)
                .foregroundStyle(InkColor.textFaint)
                .frame(minHeight: InkMetric.buttonHeight, alignment: .leading)
        }
        // 選べない択は出さない(見せて禁じない。要件 Z1)
    }

    private func run(_ option: RecoveryOption, _ target: SaveSlot?) {
        guard !working else { return }
        working = true
        Task {
            problem = await store.recoverUndoable(option, target: target, label: label(option))
            working = false
        }
    }

    @MainActor private func label(_ option: RecoveryOption) -> String {
        switch option {
        case .restart: UIText.shared.string("ui.button.new_game")
        case .rewindWithMemory: UIText.shared.string("ui.button.recovery_rewind")
        case .continueWithLoss: UIText.shared.string("ui.button.recovery_continue")
        case .loadSavePoint: UIText.shared.string("ui.button.recovery_load")
        }
    }
}

/// 4 択の文言(画面の固定文言)。
struct RecoveryLabel: View {
    let option: RecoveryOption

    var body: some View {
        switch option {
        case .restart: ui("ui.button.new_game")
        case .rewindWithMemory: ui("ui.button.recovery_rewind")
        case .continueWithLoss: ui("ui.button.recovery_continue")
        case .loadSavePoint: ui("ui.button.recovery_load")
        }
    }
}

/// 保存の枠の名前(「3 日目の夜明け」「手動 1」)。
struct SlotLabel: View {
    let slot: SaveSlot

    var body: some View { slotText(slot) }
}

/// 保存の枠の名前(画面の固定文言)。
@MainActor func slotText(_ slot: SaveSlot) -> Text {
    switch slot {
    case .dawn(let d): ui("ui.body.slot_dawn", ["day": .int(d)])
    case .manual(let i): ui("ui.body.slot_manual", ["number": .int(i + 1)])
    case .resume, .screen: ui("ui.body.slot_resume")
    }
}

extension SavePointGroups {
    /// 読める枠だけ(読めない枠は、押せないのでボタンにせず出さない)。
    var readable: SavePointGroups {
        SavePointGroups(auto: auto.filter { $0.problem == nil }, manual: manual.filter { $0.problem == nil })
    }

    var isEmpty: Bool { auto.isEmpty && manual.isEmpty }
}

/// 「セーブから読む」の一覧: 自動(夜明けの記録)と手動(自分の記録)の 2 つの節。中身のある枠だけを並べ、
/// 選ぶと pick を呼ぶ。空の節は見出しごと出さない。ゲームオーバーの 4 択とタイトルが使う。
struct SavePointSections: View {
    let groups: SavePointGroups
    let pick: (SaveSlot) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: InkMetric.gap) {
            if !groups.auto.isEmpty {
                InkSection(title: ui("ui.body.records_auto")) {
                    ForEach(groups.auto, id: \.slot) { p in
                        Button { pick(p.slot) } label: {
                            InkRow(title: slotText(p.slot), value: ui("ui.button.save_read"))
                        }
                        .buttonStyle(.inkRow)
                        .accessibilityIdentifier("load-\(p.slot.fileStem)")
                    }
                }
            }
            if !groups.manual.isEmpty {
                InkSection(title: ui("ui.body.records_manual")) {
                    ForEach(groups.manual, id: \.slot) { p in
                        Button { pick(p.slot) } label: {
                            InkRow(title: slotText(p.slot),
                                   value: p.summary.map { ui("ui.body.slot_day", ["day": .int($0.day)]) })
                        }
                        .buttonStyle(.inkRow)
                        .accessibilityIdentifier("load-\(p.slot.fileStem)")
                    }
                }
            }
        }
    }
}
