import SwiftUI
import ReForgeCore

/// S1 拠点(MVP の主画面)。
struct BaseView: View {
    @Bindable var session: GameSession
    let app: AppModel
    @State private var confirmRest = false
    @State private var confirmTitle = false
    @Environment(\.scenePhase) private var scenePhase

    private var s: GameState { session.state }
    private var t: GameText { session.text }
    private var isNight: Bool { s.phase == .night }
    private var outdoorOK: Bool { s.phase == .day }

    var body: some View {
        VStack(spacing: 0) {
            statusBar
                .padding(.horizontal, 16)
                .padding(.top, AdLayout.contentGap)
                .padding(.bottom, 8)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let notice = session.notice {
                        NoticeBanner(text: notice.text, id: notice.id)
                    }
                    warnings
                    buildingChips
                    inventoryGrid
                }
                .padding(16)
            }
            actionButtons
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, AdLayout.bottomButtonGap)
        }
        .task(id: scenePhase) { await runClock() }
        .sheet(item: $session.sheet) { sheet in
            sheetView(sheet)
        }
        .fullScreenCover(isPresented: Binding(get: { session.gameOverReason != nil }, set: { _ in })) {
            GameOverView(session: session, app: app)
        }
        .fullScreenCover(isPresented: Binding(get: { session.isVictory }, set: { _ in })) {
            VictoryView(session: session, app: app)
        }
        .confirmationDialog(Text(verbatim: t.restConfirm(s)), isPresented: $confirmRest, titleVisibility: .visible) {
            Button("休む") { session.perform(.rest) }
            Button("やめる", role: .cancel) {}
        }
        .alert("タイトルへ戻りますか?", isPresented: $confirmTitle) {
            Button("タイトルへ") { app.backToTitle() }
            Button("やめる", role: .cancel) {}
        } message: {
            Text("いまの状態は保存されます。")
        }
    }

    // MARK: 時計

    /// 昼の時計。アクティブな間だけ回り、実時間の経過を Game に渡す。
    private func runClock() async {
        guard scenePhase == .active else { return }
        let clock = ContinuousClock()
        var last = clock.now
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(200))
            let now = clock.now
            let dt = now - last
            last = now
            let seconds = Double(dt.components.seconds) + Double(dt.components.attoseconds) / 1e18
            session.advanceClock(by: min(seconds, 1))
        }
    }

    // MARK: 上部

    private var statusBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: t.dayLabel(s.day))
                    .font(.headline)
                    .accessibilityIdentifier("dayLabel")
                if s.phase == .day || isNight {
                    Text(verbatim: t.actionsLabel(s))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("actionsLabel")
                }
            }
            Spacer()
            if s.phase == .day {
                ProgressView(value: session.dayRemainingFraction)
                    .frame(width: 110)
                    .tint(.orange)
                    .accessibilityLabel(Text("昼の残り"))
                    .accessibilityIdentifier("clockBar")
                Button {
                    if session.isPaused { session.play() } else { session.pause() }
                } label: {
                    Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(session.isPaused ? Text("再開") : Text("一時停止"))
                .accessibilityIdentifier("pauseButton")
            } else if isNight {
                Text("夜")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.indigo.opacity(0.5)))
            }
            Menu {
                Button {
                    session.manualSave()
                } label: {
                    Label("ここまでを記録する", systemImage: "square.and.arrow.down")
                }
                .disabled(!s.isActive)
                Button {
                    session.sheet = .settings
                } label: {
                    Label("設定", systemImage: "gearshape")
                }
                Button {
                    confirmTitle = true
                } label: {
                    Label("タイトルへ", systemImage: "house")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel(Text("メニュー"))
        }
    }

    // MARK: 中段

    @ViewBuilder
    private var warnings: some View {
        ForEach(Array(t.warnings(s).enumerated()), id: \.offset) { _, w in
            Text(verbatim: w.text)
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(w.level == .danger ? Color.red.opacity(0.35) : Color.yellow.opacity(0.3)))
        }
    }

    @ViewBuilder
    private var buildingChips: some View {
        if !s.buildings.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(s.buildings, id: \.id) { b in
                        Text(verbatim: session.game.content.buildingName(b.id))
                            .font(.subheadline)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.secondary.opacity(0.25)))
                    }
                }
            }
            .accessibilityIdentifier("buildingChips")
        }
    }

    private var inventoryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(session.game.content.items, id: \.id) { item in
                let empty = s.quantity(item.id) == 0
                HStack {
                    Text(verbatim: item.name)
                    Spacer()
                    Text(verbatim: t.stockLabel(item.id, in: s))
                        .monospacedDigit()
                }
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.15)))
                .opacity(empty ? 0.45 : 1)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("stock-\(item.id)")
            }
        }
    }

    // MARK: 下段

    private var actionButtons: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                actionButton("採取する", enabled: outdoorOK) { session.sheet = .gather }
                    .accessibilityIdentifier("gatherButton")
                actionButton("作る", enabled: s.phase == .day || isNight) { session.sheet = .craft }
                    .accessibilityIdentifier("craftButton")
            }
            HStack(spacing: 8) {
                actionButton("建てる", enabled: outdoorOK) { session.sheet = .build }
                    .accessibilityIdentifier("buildButton")
                actionButton("日誌", enabled: true) { session.sheet = .journal }
                    .accessibilityIdentifier("journalButton")
            }
            Button {
                if isNight || s.phase == .dusk {
                    session.perform(.rest)
                } else if s.actionPointsLeft > 0 {
                    confirmRest = true
                } else {
                    session.perform(.rest)
                }
            } label: {
                Group {
                    if isNight || s.phase == .dusk { Text("寝る") } else { Text("休む") }
                }
                .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!s.isActive)
            .accessibilityIdentifier("restButton")
        }
    }

    /// 押せない時間帯でも押せる形にしておき、押したら理由を出す(「暗くて外には出られない」)。
    private func actionButton(_ title: LocalizedStringKey, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            if enabled {
                action()
            } else {
                session.show(t.message(for: .notAllowed(s.phase)))
            }
        } label: {
            Text(title).frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.bordered)
        .opacity(enabled ? 1 : 0.4)
        .disabled(!s.isActive)
    }

    @ViewBuilder
    private func sheetView(_ sheet: ActiveSheet) -> some View {
        switch sheet {
        case .gather: GatherSheet(session: session)
        case .craft: CraftSheet(session: session)
        case .build: BuildSheet(session: session)
        case .journal: JournalView(session: session)
        case .settings: SettingsView(app: app)
        case .nightfall: NightfallSheet(session: session)
        case .dawn: DawnSheet(session: session)
        }
    }
}

/// 短い一言(数秒で消える)。
struct NoticeBanner: View {
    let text: String
    let id: Int
    @State private var visible = true

    var body: some View {
        Group {
            if visible {
                Text(verbatim: text)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.3)))
                    .transition(.opacity)
            }
        }
        .task(id: id) {
            visible = true
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation { visible = false }
        }
        .accessibilityIdentifier("notice")
    }
}
