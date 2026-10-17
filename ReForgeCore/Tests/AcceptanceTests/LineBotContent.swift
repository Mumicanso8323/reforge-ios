import Foundation
import ReForgeEngine
import RFTestSupport

/// W-05 uses the generated layer when it is available.  The public fixture has
/// the same neutral identifiers and the measured production numbers otherwise.
enum LineBotContent {
    enum Source: String { case generated, publicBundle }

    static func load() throws -> (content: ContentDB, source: Source) {
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
    static let mine: HandworkID = "handwork.mine"
    static let smelt: HandworkID = "handwork.smelt"
    static let hammer: HandworkID = "handwork.hammer"
    static let chopWood: InteractionID = "interaction.chop_wood"
    static let burnCharcoal: InteractionID = "interaction.burn_charcoal"
    static let wood: ItemID = "wood"
    static let charcoal: ItemID = "charcoal"
    static let coal: ItemID = "coal"
    static let stone: ItemID = "stone"
    static let clay: ItemID = "clay"
    static let useBlade = false
}
