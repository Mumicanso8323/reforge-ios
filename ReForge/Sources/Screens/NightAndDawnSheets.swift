import SwiftUI
import ReForgeCore

/// S1-N 日が沈んだ。夜作業をするか、朝まで寝るか。
struct NightfallSheet: View {
    let session: GameSession

    var body: some View {
        let canWork = session.game.canStartNightWork(session.state)
        VStack(spacing: 20) {
            Spacer()
            Text("日が沈んだ")
                .font(.title.bold())
            Text("夜は長い。火のそばで作業を続けるか、朝まで眠るか。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            VStack(spacing: 12) {
                Button {
                    session.startNightWork()
                } label: {
                    Text("夜作業をする").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!canWork)
                .accessibilityIdentifier("nightWorkButton")
                if !canWork {
                    Text(verbatim: session.text.message(for: .noFireAtNight))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button {
                    session.sleep()
                } label: {
                    Text("寝る").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("sleepButton")
            }
            .controlSize(.large)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24 + AdLayout.bottomButtonGap)
        .interactiveDismissDisabled()
    }
}

/// 「寝る」の結果シート。日誌の集計行と同じ中身。
struct DawnSheet: View {
    let session: GameSession

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("長い夜が明けた")
                .font(.title.bold())
            Text(verbatim: session.text.dayLabel(session.state.day))
                .font(.headline)
                .foregroundStyle(.secondary)
            if let report = session.state.lastDawn {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(session.text.dawnLines(report), id: \.self) { line in
                        Text(verbatim: line)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.15)))
            }
            ForEach(Array(session.text.warnings(session.state).enumerated()), id: \.offset) { _, w in
                Text(verbatim: w.text)
                    .font(.subheadline.bold())
                    .foregroundStyle(w.level == .danger ? Color.red : Color.yellow)
            }
            Spacer()
            Button {
                session.beginMorning()
            } label: {
                Text("朝をむかえる").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("morningButton")
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24 + AdLayout.bottomButtonGap)
        .interactiveDismissDisabled()
    }
}
