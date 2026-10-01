import SwiftUI
import ReForgeCore

/// S7 日誌。日ごとのセクション(新しい日が上)。
struct JournalView: View {
    let session: GameSession
    @Environment(\.dismiss) private var dismiss

    private var days: [(day: Int, entries: [LogEntry])] {
        let grouped = Dictionary(grouping: session.state.log, by: \.day)
        return grouped.keys.sorted(by: >).map { (day: $0, entries: grouped[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(days, id: \.day) { group in
                    Section {
                        ForEach(Array(group.entries.enumerated().reversed()), id: \.offset) { _, entry in
                            Text(verbatim: session.text.journal(entry))
                                .font(.subheadline)
                        }
                    } header: {
                        Text(verbatim: session.text.dayLabel(group.day))
                    }
                }
            }
            .navigationTitle(Text("日誌"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}
