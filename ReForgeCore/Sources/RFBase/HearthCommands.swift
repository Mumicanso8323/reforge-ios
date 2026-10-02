import RFContent
import RFKernel
import RFRules
import RFWorld

/// 火床へのプレイヤーの操作(くべる・積む・点け直す・埋める)。燃料は拠点の蓄えから取る。持ち主: U21
enum HearthCommands {
    static func handle(_ id: EntityID, _ op: HearthOp, _ ctx: inout StepContext) -> CommandResult {
        guard let p = ctx.world.placements.items[id], let d = Hearths.def(p, ctx.content),
              var s = Hearths.state(p, ctx.content) else { return .rejected(Rejection("reason.hearth.none")) }
        if case .underConstruction = p.status { return .rejected(Rejection("reason.hearth.unbuilt")) }
        if p.status == .broken { return .rejected(Rejection("reason.hearth.broken")) }
        switch op {
        case .stoke(let item):
            guard HearthRule.fuelValue(item, d) != nil else { return .rejected(Rejection("reason.hearth.not_fuel")) }
            guard s.fuel < d.capSeconds * 1000 else { return .rejected(Rejection("reason.hearth.full")) }
            guard take(item, 1, &ctx) else { return .rejected(Rejection("reason.hearth.no_fuel")) }
            s = HearthRule.add(s, d, item: item, quantity: 1) ?? s
            if s.lit { s.banked = false }
        case .stack(let item, let count):
            guard let pile = d.pileItem, pile == item, count > 0 else { return .rejected(Rejection("reason.hearth.not_fuel")) }
            let room = (d.pileMax ?? HearthRule.defaultPileMax) - s.pile
            guard room > 0 else { return .rejected(Rejection("reason.hearth.pile_full")) }
            let n = min(room, count)
            guard take(item, n, &ctx) else { return .rejected(Rejection("reason.hearth.no_fuel")) }
            s.pile += n
        case .ignite(let from):
            guard !s.lit || s.banked else { return .rejected(Rejection("reason.hearth.already_lit")) }
            guard s.fuel > 0 || d.igniteSeconds != nil else { return .rejected(Rejection("reason.hearth.no_fuel")) }
            if !s.lit, d.needsFlame ?? true {
                guard let f = from, f != id, let fp = ctx.world.placements.items[f],
                      let fl = Hearths.level(of: fp, ctx.content), fl != .out
                else { return .rejected(Rejection("reason.hearth.no_flame")) }
            }
            s = HearthRule.kindle(s, d)
            s.lit = true
            s.banked = false
        case .bank:
            guard s.lit else { return .rejected(Rejection("reason.hearth.out")) }
            s.banked = true
        }
        Hearths.write(id, s, &ctx)
        ctx.changes.mark([.placements, .inventory])
        return .done
    }

    /// 拠点の蓄えから n 個取る(全部そろわなければ何も取らない)。
    static func take(_ item: ItemID, _ n: Int, _ ctx: inout StepContext) -> Bool {
        let have = ctx.world.inventory.entries(.base).filter { $0.stuff == .item(item) && $0.unique == nil }
            .reduce(0) { $0 + $1.quantity }
        guard have >= n else { return false }
        return ctx.takeStock(n, from: .base, where: { $0.stuff == .item(item) && $0.unique == nil }) != nil
    }
}
