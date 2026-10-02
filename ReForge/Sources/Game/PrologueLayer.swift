import SwiftUI
import ReForgeEngine

/// 冒頭の文章だけを読む地図上の層。場面の本文は本体から受け取る。
struct PrologueLayer: View {
    let prologue: PrologueView
    let store: GameStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visibleLines = 0
    @State private var arrowVisible = true

    var body: some View {
        InkColor.field
            .overlay {
                VStack(alignment: .leading, spacing: InkFont.bodyLineSpacing) {
                    ForEach(Array(prologue.lines.enumerated()), id: \.offset) { index, line in
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(verbatim: line)
                            if index == prologue.lines.indices.last, prologue.waiting {
                                Text(verbatim: "▼")
                                    .font(InkFont.font(12, relativeTo: .caption))
                                    .opacity(arrowVisible ? 1 : 0.25)
                            }
                        }
                        .font(InkFont.font(17, relativeTo: .body))
                        .foregroundStyle(InkColor.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .opacity(index < visibleLines ? 1 : 0)
                        .offset(y: index < visibleLines || reduceMotion ? 0 : 8)
                    }
                }
                .padding(InkMetric.gutter)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            .contentShape(Rectangle())
            .onTapGesture { advance() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: prologue.lines.joined(separator: "\n")))
            .accessibilityAction(.default) { advance() }
            .onAppear {
                reveal(prologue.lines, announce: false)
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    arrowVisible = false
                }
            }
            .onChange(of: prologue.lines) { _, lines in
                reveal(lines, announce: true)
            }
    }

    private func advance() {
        store.send(.narrative(.advanceScene))
    }

    private func reveal(_ lines: [String], announce: Bool) {
        visibleLines = max(0, lines.count - 1)
        let show = { visibleLines = lines.count }
        if reduceMotion {
            show()
        } else {
            withAnimation(.easeOut(duration: 0.4)) { show() }
        }
        if announce, let line = lines.last {
            AccessibilityNotification.Announcement(line).post()
        }
    }
}
