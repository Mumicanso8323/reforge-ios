import Foundation
import ReForgeEngine
import RFTestSupport

/// W-05 uses the generated layer when it is available.  The public fixture has
/// the same neutral identifiers and the measured production numbers otherwise.
enum LineBotContent {
    enum Source: String { case generated, publicBundle }

    static func load() throws -> (content: ContentDB, source: Source) {
        // 非公開の層があれば生成したコンテンツで測る。REFORGE_W05_SOURCE=public なら、層があっても公開の束(突き合わせ用)。
        if ProcessInfo.processInfo.environment["REFORGE_W05_SOURCE"] != "public", TestContent.hasPrivateLayer {
            return (try TestContent.full(), .generated)
        }
        var content = try TestContent.publicOnly()
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/LineBotPublicBundle.json")
        try ContentLoader.apply(json: Data(contentsOf: url), to: &content, name: "line-bot-public")
        return (content, .publicBundle)
    }
}

/// Identifiers used by the W-05 driver.  Quantities deliberately live in the
/// content bundle, not in the bot policy.
struct LineBotKit {
    static let minehead: ModuleKindID = "minehead"
    static let furnace: ModuleKindID = "furnace"
    static let anvil: ModuleKindID = "anvil"
    static let kiln: StructureKindID = "charcoal_kiln"
    static let campfire: StructureKindID = "campfire"
    static let mine: HandworkID = "handwork.mine"
    static let mineByHand: InteractionID = "interaction.mine_by_hand"
    static let smelt: HandworkID = "handwork.smelt"
    static let hammer: HandworkID = "handwork.hammer"
    static let chopWood: InteractionID = "interaction.chop_wood"
    static let burnCharcoal: InteractionID = "interaction.burn_charcoal"
    static let stoneHammer: ItemID = "stone_hammer"
    static let wood: ItemID = "wood"
    static let charcoal: ItemID = "charcoal"
    static let coal: ItemID = "coal"
    static let stone: ItemID = "stone"
    static let clay: ItemID = "clay"
    static let useBlade = false
    /// 手作業ボットも 1 日目に掘って、鉱石を 2 日目へ持ち越す(手作業に有利。既定は真)。REFORGE_W05_HAND_DAY1=0 で、
    /// 1 日目は何もしない(炉が無いので 0 枚)手作業にして、手の最良日を比べられる。ラインのボットは 1 日目に必ず掘る。
    static let handMinesOnDayOne = ProcessInfo.processInfo.environment["REFORGE_W05_HAND_DAY1"] != "0"
}
