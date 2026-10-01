// swift-tools-version:5.9
// ReForgeCore: ゲームロジック本体。UIKit / SwiftUI に依存しない純 Swift(Linux でもビルド・テストできること)。
// ReForgeContent: 原本から抜き出したコンテンツ JSON と MVP 用オーバーライドを読み込む。
import PackageDescription

let package = Package(
    name: "ReForgeCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ReForgeCore", targets: ["ReForgeCore", "ReForgeContent"]),
        .library(name: "RFMap", targets: ["RFMap"]),
    ],
    targets: [
        .target(name: "ReForgeCore"),
        // RFMap: 地図(地形・POI・鉱脈・視界・経路)。他のターゲットに依存しない。
        .target(name: "RFMap"),
        .target(
            name: "ReForgeContent",
            dependencies: ["ReForgeCore"],
            resources: [.copy("Resources")]
        ),
        .testTarget(name: "ReForgeCoreTests", dependencies: ["ReForgeCore", "ReForgeContent"]),
        .testTarget(name: "RFMapTests", dependencies: ["RFMap"]),
    ]
)
