import SwiftUI
import UIKit
import ReForgeEngine

/// 序の見せ方の 3 案(PT-B6 §2)。既定は A。切り替えは UserDefaults の `ReForgePrologueStyle`(a / b / c。
/// 起動引数 `-ReForgePrologueStyle b` でも入る)。語りの文・行の数・順番は変えない。見せ方だけが違う。
enum PrologueStyle: String, CaseIterable {
    case a, b, c

    static let defaultsKey = "ReForgePrologueStyle"

    static var current: PrologueStyle {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(PrologueStyle.init(rawValue:)) ?? .a
    }
}

/// 序の間だけ、画面全体を覆う語りの場面(PT-B6)。地図・帯・タブ・角のボタンは、序の間は作らない。
/// 場面の本文は呼び出す側から受け取る(本体の PrologueView.lines。公開の層の見本は Debug/PrologueSample.swift)。
/// 送りはタップだけ(時間では送らない)。押せる範囲は全画面。確認のダイアログは出さない。
/// exiting が true のときは、送りを受けず、終わりの移り(文字 0.6 秒で消え → 黒 0.3 秒 → 覆いが 0.8 秒で消える)を演じて
/// onExitDone を呼ぶ。「動きを減らす」の入では 0.3 秒のフェードだけ。
struct PrologueScene: View {
    var kind: PrologueView.Kind = .prologue
    let lines: [String]
    var speakers: [String?] = []
    var style: PrologueStyle = .current
    var exiting = false
    var advance: () -> Void = {}
    var onExitDone: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var lineGap: CGFloat = 19 * 0.6

    /// 浮かび終えた(または浮かんでいる)行の数。
    @State private var shown = 0
    /// 1 字ずつの案(B): 最後の行の出た文字数。
    @State private var typed = 0
    @State private var typing = false
    @State private var arrowReady = false
    @State private var arrowDim = false
    @State private var pressed = false
    @State private var textOpacity = 1.0
    @State private var sceneOpacity = 1.0
    @State private var groundDark = false
    @State private var job: Task<Void, Never>?

    private static let fontSize: CGFloat = 19

    var body: some View {
        GeometryReader { geo in
            ZStack {
                (groundDark ? Color.black : InkColor.prologueGround)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { tapped() }
                textBlock(height: geo.size.height)
                    .allowsHitTesting(false)
            }
        }
        .opacity(sceneOpacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: lines.joined(separator: "\n")))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("prologueScene")
        .accessibilityAction(.default) { tapped() }
        .onAppear {
            if exiting {
                runExit()
            } else {
                show(lines: lines, announce: false)
                startBlink()
            }
        }
        .onChange(of: lines) { _, new in
            guard !exiting else { return }
            show(lines: new, announce: true)
        }
        .onDisappear { job?.cancel() }
    }

    // MARK: - 描く

    private func textBlock(height: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: lineGap) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        VStack(alignment: .leading, spacing: 3) {
                            if speakers.indices.contains(index), let speaker = speakers[index] {
                                Text(verbatim: speaker)
                                    .font(InkFont.small)
                                    .foregroundStyle(InkColor.textDim)
                                    .accessibilityIdentifier("stage-speaker-\(index)")
                            }
                            lineView(index: index, line: line)
                        }
                    }
                    Text(verbatim: "▼")
                        .font(InkFont.font(14, relativeTo: .caption))
                        .foregroundStyle(InkColor.textDim)
                        .opacity(arrowReady && !exiting ? (arrowDim ? 0.25 : 1) : 0)
                        .offset(y: pressed ? 4 : 0)
                        .animation(.easeOut(duration: 0.08), value: pressed)
                        .accessibilityHidden(true)
                        .id("prologue-end")
                }
                .padding(.horizontal, 32)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollDisabled(true)
            .frame(height: height * 0.5)
            .mask(
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.14),
                                       .init(color: .black, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            )
            .opacity(textOpacity)
            .onChange(of: lines.count) { _, _ in
                proxy.scrollTo("prologue-end", anchor: .bottom)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, height * 0.2)
    }

    @ViewBuilder
    private func lineView(index: Int, line: String) -> some View {
        let isLast = index == lines.count - 1
        let partial = (style == .b && isLast && !exiting) ? String(line.prefix(typed)) : line
        // 全部の字で場所を取り、出ていない字は見えなくする(字が出ても行が動かない)
        Text(verbatim: line)
            .opacity(0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topLeading) {
                Text(verbatim: partial)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(InkFont.font(Self.fontSize, relativeTo: .body))
            .foregroundStyle(InkColor.text)
            .fixedSize(horizontal: false, vertical: true)
            .opacity(index < shown ? olderOpacity(index) : 0)
            .offset(y: index < shown || reduceMotion ? 0 : 8)
    }

    /// 入りきらなくなった行を、古い方から薄くして上へ流す(上の端は mask でも消える)。
    private func olderOpacity(_ index: Int) -> Double {
        let age = lines.count - 1 - index
        return age <= 3 ? 1 : max(0.3, 1 - 0.2 * Double(age - 3))
    }

    // MARK: - 動き

    private var floatDuration: Double { style == .c ? 0.8 : 0.5 }

    private func show(lines new: [String], announce: Bool) {
        job?.cancel()
        let count = new.count
        // 場面が替わって行が減ったときは数え直す
        shown = min(shown, max(0, count - 1))
        arrowReady = false
        typed = 0
        typing = false
        if announce, let line = new.last {
            AccessibilityNotification.Announcement(line).post()
        }
        let last = new.last ?? ""
        let reduce = reduceMotion
        let styleNow = style
        let duration = floatDuration
        job = Task { @MainActor in
            if reduce {
                shown = count
                typed = last.count
                arrowReady = true
                return
            }
            withAnimation(.easeOut(duration: duration)) { shown = count }
            if styleNow == .b {
                typing = true
                var n = 0
                for ch in last {
                    try? await Task.sleep(for: .milliseconds(40 + (Self.isPunctuation(ch) ? 120 : 0)))
                    if Task.isCancelled { return }
                    n += 1
                    typed = n
                }
                typing = false
                try? await Task.sleep(for: .milliseconds(400))
            } else {
                typed = last.count
                try? await Task.sleep(for: .milliseconds(Int(duration * 1000) + 400))
            }
            if Task.isCancelled { return }
            withAnimation(.easeOut(duration: 0.2)) { arrowReady = true }
        }
    }

    private static func isPunctuation(_ ch: Character) -> Bool {
        "、。，．,.!?！？…".contains(ch)
    }

    private func startBlink() {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
            arrowDim = true
        }
    }

    private func tapped() {
        guard !exiting else { return }
        pressed = true
        UISelectionFeedbackGenerator().selectionChanged()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            pressed = false
        }
        // 1 字ずつの案: 出ている途中のタップは、その行を全部出す(送らない)
        if style == .b, typing {
            job?.cancel()
            typing = false
            typed = lines.last?.count ?? 0
            shown = lines.count
            job = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                if Task.isCancelled { return }
                withAnimation(.easeOut(duration: 0.2)) { arrowReady = true }
            }
            return
        }
        advance()
    }

    private func runExit() {
        shown = lines.count
        typed = lines.last?.count ?? 0
        let reduce = reduceMotion
        job = Task { @MainActor in
            switch kind {
            case .stage:
                if reduce {
                    sceneOpacity = 0
                } else {
                    withAnimation(.easeOut(duration: 0.3)) { sceneOpacity = 0 }
                    try? await Task.sleep(for: .milliseconds(300))
                }
                if !Task.isCancelled { onExitDone() }
                return
            case .prologue:
                break
            }
            if reduce {
                withAnimation(.easeInOut(duration: 0.3)) { sceneOpacity = 0 }
                try? await Task.sleep(for: .milliseconds(300))
            } else {
                withAnimation(.easeIn(duration: 0.6)) {
                    textOpacity = 0
                    groundDark = true
                }
                try? await Task.sleep(for: .milliseconds(900))  // 文字が消える 0.6 秒 + 黒の間 0.3 秒
                if Task.isCancelled { return }
                withAnimation(.easeOut(duration: 0.8)) { sceneOpacity = 0 }
                try? await Task.sleep(for: .milliseconds(800))
            }
            if Task.isCancelled { return }
            onExitDone()
        }
    }
}
