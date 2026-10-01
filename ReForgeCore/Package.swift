// swift-tools-version:5.9
// ReForgeCore: ゲームロジック本体。UIKit / SwiftUI に依存しない純 Swift(Linux でもビルド・テストできること)。
import PackageDescription

let package = Package(
    name: "ReForgeCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ReForgeCore", targets: ["ReForgeCore"]),
    ],
    targets: [
        .target(name: "ReForgeCore"),
        .testTarget(name: "ReForgeCoreTests", dependencies: ["ReForgeCore"]),
    ]
)
