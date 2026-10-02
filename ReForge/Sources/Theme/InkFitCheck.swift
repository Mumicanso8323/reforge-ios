import SwiftUI

#if DEBUG
import Observation

/// 文字が枠に収まらない(切れる・省略記号になる)要素の一覧。撮る起動のとき UI テストが読む(Debug/ScreenshotMode.swift の印)。
@MainActor
@Observable
final class InkFitLog {
    static let shared = InkFitLog()
    private var entries: [UUID: String] = [:]

    func set(_ token: UUID, _ entry: String?) {
        if entries[token] != entry { entries[token] = entry }
    }

    /// 当たった要素の識別子と大きさ(文字そのものは含めない)を、並べて 1 行にしたもの。無ければ空。
    var report: String { entries.values.sorted().joined(separator: ";") }
}

private struct InkFitIdealHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// 要素の「理想の高さ」(行数の制限を外し、実際に置かれた幅で組んだ高さ)と、実際の高さを比べる。
/// 理想が実際より大きければ、文字が切れている(lineLimit・frame に負けた)。
/// 撮る起動のときだけ働く。lineLimit・frame はこの修飾子より外に置くこと(内側に置くと理想の測りにも効いてしまう)。
private struct InkFitCheck: ViewModifier {
    let id: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if ScreenshotMode.isActive {
            content.background(
                GeometryReader { actual in
                    content
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: actual.size.width, alignment: .topLeading)
                        .hidden()
                        .background(
                            GeometryReader { ideal in
                                Color.clear.preference(key: InkFitIdealHeightKey.self, value: ideal.size.height)
                            }
                        )
                        .overlayPreferenceValue(InkFitIdealHeightKey.self) { ideal in
                            InkFitReporter(id: id, actual: actual.size, ideal: ideal)
                        }
                }
            )
        } else {
            content
        }
    }
}

/// 比べた結果の印。要素の識別子と accessibilityValue("overflow")を持つ、触れない透明の面。
private struct InkFitReporter: View {
    let id: String
    let actual: CGSize
    let ideal: CGFloat
    @State private var token = UUID()

    private var overflow: Bool { actual.width > 0 && ideal > actual.height + 1 }

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityIdentifier(id)
            .accessibilityValue(Text(verbatim: overflow ? "overflow" : ""))
            .onChange(of: overflow, initial: true) { _, now in
                InkFitLog.shared.set(token, now ? "\(id) \(Int(actual.width))x\(Int(actual.height)) ideal-h \(Int(ideal))" : nil)
            }
            .onDisappear { InkFitLog.shared.set(token, nil) }
    }
}

extension View {
    /// 文字が枠から切れていないかを測る(撮る起動のときだけ)。Theme の部品が文字に付ける。
    func inkFitCheck(id: String) -> some View { modifier(InkFitCheck(id: id)) }
}
#else
extension View {
    /// release では何もしない(Theme の部品が同じ書き方で呼べるように)。
    func inkFitCheck(id: String) -> some View { self }
}
#endif
