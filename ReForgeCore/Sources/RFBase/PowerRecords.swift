import RFContent
import RFKernel
import RFRules
import RFWorld

/// 電気を出す建造物(provides["power"] が 1 以上)が建ち終わって働き始めたステップの記録(W-24)。
///
/// 「働いている」= 建ち終わっていて(壊れていない)、whenLit の条件が効いている間。止まって再び働き始めた時も記録する。
/// 前のステップに働いていたかは建造物の parameters["powered"](1 = 働いていた)に持つ(保存の形は変えない。
/// parameters は種類ごとの値の表で、キーが増えるだけ)。電気を出すモジュールは RFProduction が同じ札を付ける。
enum PowerRecords {
    static let key = "powered"

    static func advance(_ ctx: inout StepContext) {
        for id in ctx.world.placements.items.keys.sorted() {
            guard let p = ctx.world.placements.items[id], case .structure(let kind) = p.kind, p.structure != nil,
                  (ctx.content.structures[kind]?.provides["power"] ?? 0) > 0 else { continue }
            let active = p.status == .running && Hearths.effectsActive(p, ctx.content)
            let was = (p.structure?.parameters[key] ?? 0) != 0
            guard active != was else { continue }
            ctx.world.placements.items[id]?.structure?.parameters[key] = active ? 1 : 0
            guard active else { continue }
            let rec = ctx.recordIndustry(.powered, .structure(kind, id), place: p.at, every: IndustryRecords.powered,
                                         first: IndustryRecords.firstPower)
            ctx.emit(.placementPowered(placement: id, record: rec))
            ctx.changes.mark(.placements)
        }
    }
}
