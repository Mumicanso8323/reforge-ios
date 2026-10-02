// swift-tools-version:5.9
// ReForgeCore パッケージ。UIKit / SwiftUI に依存しない純 Swift(Linux の swift test で全部確かめられること)。
//
// 構成と依存の向きは docs/architecture/A-modules.md が正本。上の層は下の層だけを import する。
//
//   L0 RFKernel                       型付き ID・座標・乱数・数値・時間・事実の式
//   L1 RFText RFMap  RFMatter         葉: 文言の書式 / 地図(生成・視界・経路) / 物質(純度・形・命名の部品・工程の計算)
//   L2 RFWorld  RFContent             世界状態(値型・Codable) / コンテンツのスキーマと読み込み
//   L3 RFRules  RFPerception          規則の土台(システムの約束・条件と効果の評価) / 認識の層
//   L4 RFTime RFSurvival RFInvention RFProduction RFLogistics RFCrew RFExploration
//      RFBase RFCombat RFResearch RFAbilities RFNarrative   ……システム(互いに import しない)
//      RFSave RFFailure                 保存 / 失敗と 4 択
//   L5 RFSim                          本体(固定ステップ・コマンド・システムの順番)
//   L6 RFPresent                      画面向けの射影(スナップショット・差分)
//   ReForgeEngine                     アプリが import する傘(全部を再公開)
//
import PackageDescription

/// L4 のシステム。互いには依存しない(連携は RFWorld のコマンドと出来事を通す)。
let systems = [
    "RFTime", "RFSurvival", "RFInvention", "RFProduction", "RFLogistics", "RFCrew",
    "RFExploration", "RFBase", "RFCombat", "RFResearch", "RFAbilities", "RFNarrative",
]
let systemDeps: [Target.Dependency] = ["RFKernel", "RFMap", "RFMatter", "RFWorld", "RFContent", "RFRules"]

var targets: [Target] = [
    // L0
    .target(name: "RFKernel"),
    // L1(葉)
    .target(name: "RFText", dependencies: ["RFKernel"]),
    .target(name: "RFMap", dependencies: ["RFKernel"], exclude: ["README.md"]),
    .target(name: "RFMatter", dependencies: ["RFKernel"], exclude: ["README.md"]),
    // L2
    .target(name: "RFWorld", dependencies: ["RFKernel", "RFMap", "RFMatter"]),
    // 封をした非公開の層(E-content.md §4.5)を開くのに AES-GCM を使う。Apple では CryptoKit、Linux では swift-crypto
    .target(name: "RFContent", dependencies: [
        "RFKernel", "RFText", "RFMap", "RFMatter",
        .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux])),
    ]),
    // L3
    .target(name: "RFRules", dependencies: ["RFKernel", "RFMap", "RFMatter", "RFWorld", "RFContent"]),
    .target(name: "RFPerception", dependencies: ["RFKernel", "RFMatter", "RFWorld", "RFContent"]),
    // L4(保存と失敗)
    .target(name: "RFSave", dependencies: ["RFKernel", "RFWorld"]),
    .target(name: "RFFailure", dependencies: ["RFKernel", "RFWorld", "RFContent", "RFRules", "RFSave"]),
    // L5
    .target(name: "RFSim", dependencies: ["RFKernel", "RFWorld", "RFContent", "RFRules", "RFSave", "RFFailure"]
        + systems.map { .target(name: $0) }),
    // L6
    // 設計画面の見込み・図鑑(RFInvention の Sheets・Codex)を画面向けに写すので RFInvention も直接引く(L6 → L4。向きは下向き)
    .target(name: "RFPresent", dependencies: [
        "RFKernel", "RFMap", "RFMatter", "RFWorld", "RFContent", "RFRules", "RFPerception", "RFSave", "RFFailure",
        "RFSim", "RFInvention",
    ]),
    // 傘
    .target(name: "ReForgeEngine", dependencies: [
        "RFKernel", "RFText", "RFMap", "RFMatter", "RFWorld", "RFContent", "RFRules", "RFPerception",
        "RFSave", "RFFailure", "RFSim", "RFPresent",
    ] + systems.map { .target(name: $0) }),
    // 非公開の層に封をして、アプリに埋める鍵の Swift ファイルを書く道具(CI の ios ジョブで使う。U3)
    .executableTarget(name: "rf-seal", dependencies: ["RFContent", "RFKernel"]),
    // テストの道具(公開の試験用コンテンツの場所・ボットの枠)。アプリには入れない
    .target(name: "RFTestSupport", dependencies: ["ReForgeEngine"]),
]

targets += systems.map { .target(name: $0, dependencies: systemDeps) }

/// テストはモジュールごとに 1 つ。実装担当は自分のテストターゲットだけを触る。
let testedModules = ["RFKernel", "RFText", "RFMap", "RFMatter", "RFWorld", "RFContent", "RFRules", "RFPerception",
                     "RFSave", "RFFailure", "RFSim", "RFPresent"] + systems
/// テストが #filePath で直接読む固定のファイル(SwiftPM のリソースにしない)。
let testExcludes: [String: [String]] = ["RFSave": ["Fixtures"]]
targets += testedModules.map {
    .testTarget(name: "\($0)Tests", dependencies: [.target(name: $0), "RFTestSupport"],
                exclude: testExcludes[$0] ?? [])
}
/// 受け入れテスト(TEST-R1-xx のボット走行など、複数システムをまたぐもの)
targets.append(.testTarget(name: "AcceptanceTests", dependencies: ["ReForgeEngine", "RFTestSupport"]))

let package = Package(
    name: "ReForgeCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        /// 新しい本体。新しい UI はこれだけを import する。
        .library(name: "ReForgeEngine", targets: ["ReForgeEngine"]),
    ],
    // 外部依存はこれ 1 つだけ(Linux の swift test で暗号を使うため。Apple では使わない)
    dependencies: [.package(url: "https://github.com/apple/swift-crypto.git", "3.0.0"..<"5.0.0")],
    targets: targets
)
