// swift-tools-version:5.9
// ReForgeCore: ゲームロジック本体。UIKit / SwiftUI に依存しない純 Swift(Linux でもビルド・テストできること)。
// ReForgeContent: 原本から抜き出したコンテンツ JSON と MVP 用オーバーライドを読み込む。
// RFMatter: 物質・命名・レシピの純度・連結の工程(発明)の計算。他のターゲットに依存しない葉。
import PackageDescription

let package = Package(
    name: "ReForgeCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ReForgeCore", targets: ["ReForgeCore", "ReForgeContent"]),
        .library(name: "RFMatter", targets: ["RFMatter"]),
    ],
    targets: [
        .target(name: "ReForgeCore"),
        .target(
            name: "ReForgeContent",
            dependencies: ["ReForgeCore"],
            resources: [.copy("Resources")]
        ),
        .target(name: "RFMatter"),
        .testTarget(name: "ReForgeCoreTests", dependencies: ["ReForgeCore", "ReForgeContent"]),
        .testTarget(name: "RFMatterTests", dependencies: ["RFMatter"]),
    ]
)
