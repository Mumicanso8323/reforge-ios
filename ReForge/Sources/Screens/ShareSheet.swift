import SwiftUI
import UIKit

/// 共有シート(遊んだ記録の書き出し。遊んだ人が押したときだけ開く)。
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// 共有シートに渡すファイル(sheet(item:) 用)。
struct ExportedLog: Identifiable {
    let url: URL
    var id: URL { url }
}
