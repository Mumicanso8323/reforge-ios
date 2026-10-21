import SwiftUI

/// 取り消せる選びを四秒だけ残す、地図とほかの画面で使い回す帯。
struct UndoBand: View {
    let label: String
    let seconds: Int
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            spokenText(label).lineLimit(1).minimumScaleFactor(InkMetric.minimumScale)
            Spacer(minLength: 4)
            ui("ui.band.undo_remaining", ["seconds": .int(seconds)])
                .font(InkFont.small)
                .foregroundStyle(InkColor.textDim)
            Button(action: undo) { ui("ui.button.undo") }
                .buttonStyle(.ink(.secondary, fill: false))
        }
        .padding(8)
        .frame(minHeight: 44)
        .background(InkColor.panel.opacity(0.96))
        .overlay(Rectangle().stroke(InkColor.rule, lineWidth: InkMetric.rule))
        .accessibilityIdentifier("undoBand")
    }
}
