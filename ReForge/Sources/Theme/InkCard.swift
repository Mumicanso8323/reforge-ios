import SwiftUI

/// 下からの札。iOS の .sheet / .alert / .confirmationDialog の代わり(オーナーの決め: 閉じさせるシートと確認のダイアログは出さない)。
/// - 画面の下から伸びるだけで、上に残った画面は暗くせず、押せるまま(時計も止めない)。
/// - 引き下げて閉じる操作は無い。閉じるのは札の右上の「閉じる」か、札を開いた元のボタンをもう一度押したとき。
/// - 札の中で別の操作へ進んでも、札を重ねない。
/// 使い方:
/// ```
/// someView.inkCard(isPresented: $showSettings, title: ui("ui.body.settings")) { SettingsView(app: app, close: { showSettings = false }) }
/// ```
struct InkCardModifier<CardContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let title: Text
    /// 札の高さの上限(画面の高さに対する割合)。
    var maxHeightRatio: CGFloat = 0.72
    @ViewBuilder var card: () -> CardContent

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            GeometryReader { g in
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    if isPresented {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                title
                                    .font(InkFont.heading)
                                    .tracking(InkFont.headingTracking)
                                    .inkFitCheck(id: "InkCard.title")
                                    .accessibilityAddTraits(.isHeader)
                                Spacer()
                                Button {
                                    isPresented = false
                                } label: {
                                    ui("ui.button.close")
                                }
                                .buttonStyle(.ink(.quiet, fill: false))
                                .accessibilityIdentifier("cardClose")
                            }
                            .padding(.leading, InkMetric.gutter)
                            .padding(.trailing, InkMetric.settingsReserve)
                            .padding(.top, 12)
                            .padding(.bottom, 8)
                            Rectangle().fill(InkColor.rule).frame(height: InkMetric.rule)
                            ScrollView {
                                card()
                                    .padding(InkMetric.gutter)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .scrollBounceBehavior(.basedOnSize)
                        }
                        .font(InkFont.body)
                        .foregroundStyle(InkColor.text)
                        .frame(maxWidth: .infinity, alignment: .top)
                        .frame(height: g.size.height * maxHeightRatio, alignment: .top)
                        .background(InkColor.panel)
                        .overlay(alignment: .top) {
                            Rectangle().fill(InkColor.accent).frame(height: 2)
                        }
                        .transition(.move(edge: .bottom))
                    }
                }
                .frame(width: g.size.width, height: g.size.height)
            }
            .animation(.easeOut(duration: 0.22), value: isPresented)
            .allowsHitTesting(isPresented)
        }
    }
}

extension View {
    func inkCard<C: View>(isPresented: Binding<Bool>, title: Text, maxHeightRatio: CGFloat = 0.72,
                          @ViewBuilder content: @escaping () -> C) -> some View {
        modifier(InkCardModifier(isPresented: isPresented, title: title, maxHeightRatio: maxHeightRatio, card: content))
    }
}
