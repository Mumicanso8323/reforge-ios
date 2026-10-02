import SwiftUI
import ReForgeEngine

/// 戦闘の帯(状態の帯のすぐ下。戦闘中だけ出る)。担当: U18。
/// 戦いは本体が自動で進める。画面は止めず、帯の上の並び(文字)と構え・退却だけを出す。
struct BattleBandView: View {
    let store: GameStore

    var body: some View {
        if !store.battles.isEmpty {
            InkBand(edge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(store.battles, id: \.id) { b in
                        HStack(spacing: 8) {
                            Text(verbatim: b.foe).foregroundStyle(InkColor.alert).lineLimit(1)
                            Text(verbatim: BattleBandView.lane(b))
                                .font(.custom(FontBook.mapFont, size: 15))
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            if store.ui.isOpen(UIElements.combatStance), !b.retreating {
                                Button {
                                    store.setStance(b.stance == .advance ? .keepDistance : .advance, in: b)
                                } label: { AssignText.stance(b.stance) }
                                    .buttonStyle(.ink(.secondary, fill: false))
                            }
                            if store.ui.isOpen(UIElements.combatRetreat) {
                                if b.retreating {
                                    Text("退いている").foregroundStyle(InkColor.textDim)
                                } else {
                                    Button { store.retreat(b) } label: { Text("退く") }
                                        .buttonStyle(.ink(.quiet, fill: false))
                                }
                            }
                        }
                    }
                }
            }
            .accessibilityIdentifier("battleBand")
        }
    }

    /// 帯の上の並び(1 マス 1 文字。味方と敵が同じマスなら敵を出す。空きは「・」。倒れた者は出さない)。
    static func lane(_ b: BattleBand) -> String {
        var cells = Array(repeating: "・", count: max(1, b.laneSize))
        for u in b.units where u.active && u.isAlly && cells.indices.contains(u.position) { cells[u.position] = u.glyph }
        for u in b.units where u.active && !u.isAlly && cells.indices.contains(u.position) { cells[u.position] = u.glyph }
        return cells.joined()
    }
}
