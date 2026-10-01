import SwiftUI
import ReForgeCore

/// S9 ゲームオーバー。4 つの方針を同じ見た目で並べ、プレイヤーが選ぶ(DEC-11 / OPEN-02 確定)。
/// 全画面で、広告枠は出さない。
struct GameOverView: View {
    let session: GameSession
    let app: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("拠点は持ちこたえられなかった")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .padding(.top, 48)
                if let reason = session.gameOverReason {
                    Text(verbatim: session.text.failureReasonText(reason))
                        .foregroundStyle(.secondary)
                }
                Text(verbatim: session.text.dayLabel(session.state.day))
                    .font(.headline)
                    .accessibilityIdentifier("reachedDay")

                VStack(spacing: 12) {
                    ForEach(Array(session.recoveryChoices().enumerated()), id: \.offset) { _, choice in
                        Button {
                            session.recover(choice.recovery.option)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: session.text.recoveryTitle(choice.recovery.option))
                                    .font(.headline)
                                Text(verbatim: session.text.recoveryDetail(choice.recovery, failed: session.state,
                                                                           savePoint: session.savePoint))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!choice.available)
                        .accessibilityIdentifier("recover-\(choice.recovery.option.rawValue)")
                    }
                }
                .padding(.top, 12)

                Button("タイトルへ") { app.backToTitle() }
                    .padding(.top, 8)
                    .padding(.bottom, 32)
            }
            .padding(.horizontal, 24)
        }
        .background(Color.black.ignoresSafeArea())
    }
}

/// S10 拠点が自立した(勝利)。Era 1 の認識のみ。
struct VictoryView: View {
    let session: GameSession
    let app: AppModel

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("拠点が自立した")
                .font(.largeTitle.bold())
            Text(verbatim: session.text.victoryBody(session.state))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            VStack(spacing: 12) {
                Button {
                    session.continueAfterVictory()
                } label: {
                    Text("つづける").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button {
                    app.backToTitle()
                } label: {
                    Text("タイトルへ").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
            .padding(.bottom, 32)
        }
        .padding(.horizontal, 24)
        .background(Color.black.ignoresSafeArea())
    }
}
