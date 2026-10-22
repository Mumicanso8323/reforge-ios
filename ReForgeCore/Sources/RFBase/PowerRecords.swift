import RFContent
import RFKernel
import RFRules
import RFWorld

/// 電気を出す建造物(provides["power"] が 1 以上)が建ち終わって働き始めたステップの記録(W-24)。
///
/// 「働いている」= 建ち終わっていて(壊れていない)、whenLit の条件が効いている間。止まって再び働き始めた時も記録する。
/// 前のステップに働いていたかは建造物の parameters["powered"](1 = 働いていた)に持つ。保存の中身は変わる
/// (既にある任意の表にキーが 1 つ増える)が、保存の版は上げない。キーの無い古い保存を読んだ時に二重に記録しないよう、
/// その建造物の powered の記録が ledger に既にあれば、記録せずに印だけ付ける。
/// 電気を出すモジュールは RFProduction が同じ札を付ける。
enum PowerRecords {
    static let key = "powered"

    static func advance(_ ctx: inout StepContext) {
        for id in ctx.world.placements.items.keys.sorted() {
            guard let p = ctx.world.placements.items[id], case .structure(let kind) = p.kind, p.structure != nil,
                  (ctx.content.structures[kind]?.provides["power"] ?? 0) > 0 else { continue }
            let active = p.status == .running && Hearths.effectsActive(p, ctx.content)
            let was = (p.structure?.parameters[key] ?? 0) != 0
            // 古い保存(印のキーが無い)で今は働いていない建造物は 0 を付ける(再開で記録されるように)
            if p.structure?.parameters[key] == nil, !active {
                ctx.world.placements.items[id]?.structure?.parameters[key] = 0
                continue
            }
            guard active != was else { continue }
            ctx.world.placements.items[id]?.structure?.parameters[key] = active ? 1 : 0
            guard active else { continue }
            // 古い保存(印のキー自体が無い)で、既に記録のある建造物は印だけ付ける(止まった後の再開は 0 が残るので記録する)
            if p.structure?.parameters[key] == nil,
               ctx.world.ledger.records.contains(where: { $0.act == .powered && $0.subject == .structure(kind, id) }) { continue }
            let rec = ctx.recordIndustry(.powered, .structure(kind, id), place: p.at, every: IndustryRecords.powered,
                                         first: IndustryRecords.firstPower)
            ctx.emit(.placementPowered(placement: id, record: rec))
            ctx.changes.mark(.placements)
        }
    }
}
