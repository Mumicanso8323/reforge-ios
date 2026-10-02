import SwiftUI

/// 取り消せる選びを四秒だけ残す、地図とほかの画面で使い回す帯。
struct UndoBand: View {
    let label: String
    let seconds: Int
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: label).lineLimit(1)
            Spacer(minLength: 4)
            Text("残り \(seconds) 秒")
                .font(InkFont.small)
                .foregroundStyle(InkColor.textDim)
            Button(action: undo) { Text("取り消す") }
                .buttonStyle(.ink(.secondary, fill: false))
        }
        .padding(8)
        .frame(minHeight: 44)
        .background(InkColor.panel.opacity(0.96))
        .overlay(Rectangle().stroke(InkColor.rule, lineWidth: InkMetric.rule))
    }
}
