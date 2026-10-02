import SwiftUI
import ReForgeEngine

/// ゲームオーバーの 4 択(同じ重さで並べる。推奨の順位を付けない。D-save.md §3)。
/// 確認のダイアログは出さない。取り返しのつかない「最初から」だけ長押しで確定する。
/// 選べないものは灰色にして理由を 1 行出す。巻き戻し・ロードの行き先が複数あれば、その下に並べる(既定は先頭)。
struct GameOverView: View {
    @Bindable var app: AppModel
    let store: GameStore
    @State private var choices: [RecoveryChoice] = []
    @State private var problem: String?
    @State private var working = false
    /// 選べない理由(認識の層を通した 1 行)。
    @State private var reasons: [RecoveryOption: String] = [:]

    var body: some View {
        InkPlate(title: Text("ここまで")) {
            ForEach(choices, id: \.option) { c in
                VStack(alignment: .leading, spacing: 4) {
                    row(c)
                    if !c.available, let r = reasons[c.option] {
                        Text(verbatim: r)
                            .font(InkFont.caption)
                            .foregroundStyle(InkColor.textDim)
                    }
                    if c.available, c.targets.count > 1 {
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
                Text(verbatim: problem)
                    .font(InkFont.small)
                    .foregroundStyle(InkColor.notice)
                    .accessibilityIdentifier("recoveryProblem")
            }
        }
        .disabled(working)
        .accessibilityIdentifier("gameOver")
        .task(id: store.revision) {
            choices = await store.recoveryChoices()
            var r: [RecoveryOption: String] = [:]
            for c in choices { if let id = c.reason { r[c.option] = await store.host.describe(Rejection(id)) } }
            reasons = r
        }
    }

    @ViewBuilder private func row(_ c: RecoveryChoice) -> some View {
        switch c.option {
        case .restart:
            InkHoldButton(label: Text("最初から"), hint: Text("長押しで、いまの走行を捨てて始める")) {
                run(.restart, nil)
            }
            .accessibilityIdentifier("recovery-restart")
        case .rewindWithMemory, .continueWithLoss, .loadSavePoint:
            Button { run(c.option, c.targets.first) } label: { RecoveryLabel(option: c.option) }
                .buttonStyle(.ink(.secondary))
                .disabled(!c.available)
                .accessibilityIdentifier("recovery-\(c.option.rawValue)")
        }
    }

    private func run(_ option: RecoveryOption, _ target: SaveSlot?) {
        working = true
        Task {
            problem = await store.recover(option, target: target)
            working = false
        }
    }
}

/// 4 択の文言(画面の固定文言)。
struct RecoveryLabel: View {
    let option: RecoveryOption

    var body: some View {
        switch option {
        case .restart: Text("最初から")
        case .rewindWithMemory: Text("記憶を持って巻き戻す")
        case .continueWithLoss: Text("失って続ける")
        case .loadSavePoint: Text("セーブ地点からロード")
        }
    }
}

/// 保存の枠の名前(「3 日目の夜明け」「手動 1」)。
struct SlotLabel: View {
    let slot: SaveSlot

    var body: some View { slotText(slot) }
}

/// 保存の枠の名前(画面の固定文言)。
func slotText(_ slot: SaveSlot) -> Text {
    switch slot {
    case .dawn(let d): Text("\(d) 日目の夜明け")
    case .manual(let i): Text("手動 \(i + 1)")
    case .resume, .screen: Text("つづき")
    }
}
