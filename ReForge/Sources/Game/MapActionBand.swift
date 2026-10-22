import SwiftUI
import ReForgeEngine

/// 親指の届く、地図の下端に重ねて置く時間と選びの帯(GameScreen の overlay。地図の枠は動かさない)。
struct MapActionBand: View {
    let store: GameStore
    /// 寝た夜明けの見込み(日没・夜作業の間だけ。世界の版が変わるたびに引き直す)。
    @State private var forecast: SleepForecast?

    var body: some View {
        if let pending = store.decisionUndo {
            UndoBand(label: pending.label, seconds: pending.seconds, undo: store.undoDecision)
        } else if let pending = store.timedUndo {
            UndoBand(label: pending.label, seconds: pending.seconds, undo: { _ = store.undoTimed() })
        } else if let decision = store.decision {
            // 絵は開けたときだけ(開けなければ絵なしと同じ並び)。56pt 角の切り出し。押せない。
            let artID = decision.art.flatMap { ArtProvider.shared.image($0) != nil ? $0 : nil }
            VStack(spacing: 8) {
                if let artID {
                    HStack(alignment: .top, spacing: 8) {
                        ArtView(id: artID, style: .square)
                            .frame(width: 56, height: 56)
                            .allowsHitTesting(false)
                            #if DEBUG
                            // 試験用: 切り出した 56pt 角の枠を XCUI が取れるように、透明の要素を重ねる(中の絵は切る前の大きさを返すため)
                            .overlay {
                                Color.clear
                                    .accessibilityElement()
                                    .accessibilityIdentifier("decisionArt")
                                    .allowsHitTesting(false)
                            }
                            #endif
                        if let prompt = decision.prompt {
                            spokenText(prompt)
                                .font(InkFont.body)
                                .foregroundStyle(InkColor.text)
                                .lineSpacing(InkFont.bodyLineSpacing / 2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("decisionPrompt")
                        } else {
                            Spacer(minLength: 0)
                        }
                    }
                } else if let prompt = decision.prompt {
                    spokenText(prompt)
                        .font(InkFont.body)
                        .foregroundStyle(InkColor.text)
                        .lineSpacing(InkFont.bodyLineSpacing / 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("decisionPrompt")
                }
                HStack(spacing: 8) {
                    ForEach(Array(decision.choices.enumerated()), id: \.offset) { _, choice in
                        Button { store.decide(choice.id) } label: { spokenText(choice.label).frame(maxWidth: .infinity) }
                            .buttonStyle(.ink(.secondary))
                            .frame(minHeight: InkMetric.buttonHeight)
                    }
                }
            }
            .padding(8)
            .accessibilityElement(children: .contain)
            .background(InkColor.panel.opacity(0.96))
            .accessibilityIdentifier("decisionBand")
        } else if !store.clock.bandActions.isEmpty {
            VStack(spacing: 6) {
                if let wrap = store.dayWrap, !wrap.isEmpty { DayWrapLinesView(wrap: wrap) }
                if let f = forecast, !f.isEmpty { forecastLine(f) }
                ForEach(Array(store.offers.enumerated()), id: \.offset) { _, offer in
                    offerRow(offer)
                }
                HStack(spacing: 8) {
                    ForEach(store.clock.bandActions, id: \.self) { action in
                        Button { store.choose(action) } label: { label(action).frame(maxWidth: .infinity) }
                            .buttonStyle(.ink(action == .sleep ? .primary : .secondary))
                            .accessibilityIdentifier("bandAction-\(action.rawValue)")
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity)  // 重ねの幅は地図の領域の幅(中身の理想の幅で広がって左へはみ出さない)
            .background(InkColor.panel.opacity(0.96))
            .task(id: store.revision) {
                forecast = await store.host.sleepForecast()
            }
        }
    }

    /// 寝た結果の見込みの 1 行(固定の言葉。ボタンは見込みで押せなくしない)。
    private func forecastLine(_ f: SleepForecast) -> some View {
        HStack(spacing: 10) {
            if let fire = f.fire {
                (fire == .holds ? ui("ui.band.forecast_fire_holds") : ui("ui.band.forecast_fire_dies"))
                    .foregroundStyle(fire == .dies ? InkColor.notice : InkColor.textDim)
            }
            if let furnace = f.furnace {
                (furnace == .stays ? ui("ui.band.forecast_furnace_stays") : ui("ui.band.forecast_furnace_cools"))
                    .foregroundStyle(furnace == .cools ? InkColor.notice : InkColor.textDim)
            }
        }
        .font(InkFont.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sleepForecast")
    }

    /// 申し出の 1 行: 名前 + 一言(あれば。データの文)+ 「頼む」。押したら命令を送るだけ。
    private func offerRow(_ offer: PendingOffer) -> some View {
        HStack(spacing: 8) {
            spokenText(offer.name).foregroundStyle(InkColor.text)
            if let line = offer.line {
                spokenText(line).foregroundStyle(InkColor.textDim)
            }
            Spacer(minLength: 8)
            Button { store.send(offer.command) } label: { ui("ui.button.ask") }
                .buttonStyle(.ink(.secondary))
                .frame(minHeight: InkMetric.buttonHeight)
                .accessibilityIdentifier("offer-tendFire")
        }
        .font(InkFont.small)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func label(_ action: BandAction) -> some View {
        switch action {
        case .startNightWork: ui("ui.button.night_work")
        case .sleep: ui("ui.button.sleep")
        }
    }
}

/// 帯を地図の下端に重ねる置き方の計算(純粋な関数。重ねるので、地図の枠は帯の高さによらない)。
enum BandOverlayLayout {
    /// 地図の領域(container)の中での地図の枠。帯が出ても出なくても(band が何でも)container 全体のまま。
    static func mapFrame(container: CGSize, band: CGFloat) -> CGRect {
        CGRect(origin: .zero, size: container)
    }

    /// 帯の枠。地図の領域の下端に、帯の高さ(領域の高さまで)で重なる。
    static func bandFrame(container: CGSize, band: CGFloat) -> CGRect {
        let h = min(max(band, 0), container.height)
        return CGRect(x: 0, y: container.height - h, width: container.width, height: h)
    }

    /// 帯が出ている間だけ、地図の操作部品を帯の高さぶん上げる。
    static func controlLift(band: CGFloat) -> CGFloat {
        max(band, 0)
    }

    /// 地図の高さの半分より上へは持ち上げない。
    static func controlLift(band: CGFloat, mapHeight: CGFloat) -> CGFloat {
        min(controlLift(band: band), max(mapHeight, 0) / 2)
    }
}

/// 子に高さの上限を伝え、子の大きさをそのまま返す。
/// (.frame(maxHeight:) は提案が上限より大きいと上限いっぱいに広がり、帯が地図の下端から浮く)
struct CappedHeightLayout: Layout {
    var maxHeight: CGFloat?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        return child.sizeThatFits(capped(proposal))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: capped(ProposedViewSize(bounds.size)))
    }

    private func capped(_ p: ProposedViewSize) -> ProposedViewSize {
        guard let m = maxHeight else { return p }
        return ProposedViewSize(width: p.width, height: min(p.height ?? m, m))
    }
}

/// 地図に重なる帯の実測高さを親へ渡す。
struct MapBandHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
