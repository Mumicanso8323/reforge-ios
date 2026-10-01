import RFContent
import RFKernel
import RFRules
import RFWorld

/// 電力の最小の形(U16。原作 Power/PowerGrid.cs・Generator.cs・PlacedModule の PowerDraw)。
///
/// - 発電機 = ModuleDef.power.output > 0 のモジュール。動いている(status running)間だけ出す。
///   needsWorker なら付いている人の速さ(千分率。ProductionRules.operatorSpeed)を掛ける(発電を任せる人で変わる)。
///   燃料があれば入口の燃料を 1 日あたり fuelPerDay 個ずつ燃やし、切れたら止まる(Modules.blocker)。
/// - 需要 = ModuleDef.power.draw > 0 のモジュール(壊れていないもの)の draw の合計。
/// - 結果は logistics.power["supply"]・["demand"] に書く(Modules.step の頭で、前のステップの状態から)。
///   使う側: 供給 0 で止まり、需要 > 供給 で速さ半分(Modules.blocker・Modules.speed)。
/// 電力を持つモジュールが 1 つも無い世界では何もしない(値も書かない)。
enum Power {
    static func update(_ ids: [EntityID], _ ctx: inout StepContext) {
        let w = ctx.world
        var supply = 0, demand = 0, any = false
        for id in ids {
            guard let p = w.placements.items[id], let k = p.moduleKind, let pw = ctx.content.modules[k]?.power else { continue }
            any = true
            if p.status == .broken { continue }
            if let d = pw.draw, d > 0 { demand += d }
            if let out = pw.output, out > 0, p.status == .running {
                if pw.needsWorker == true {
                    guard let op = p.module?.operatorID else { continue }
                    supply += out * max(0, ProductionRules.operatorSpeed(op, module: k, w, ctx.content)) / 1000
                } else {
                    supply += out
                }
            }
        }
        guard any || !w.logistics.power.isEmpty else { return }
        let next = any ? ["supply": supply, "demand": demand] : [:]
        if w.logistics.power != next {
            ctx.world.logistics.power = next
            ctx.changes.mark(.placements)
        }
    }

    /// 発電機の燃料を 1 ステップぶん燃やす(端数は logistics.fuelCarry)。
    static func burnFuel(_ id: EntityID, _ def: ModuleDef, _ ctx: inout StepContext) {
        guard let fuel = def.power?.fuel, let perDay = def.power?.fuelPerDay, perDay > 0 else { return }
        let day = max(1, ctx.content.clock.dayGameSeconds + ctx.content.clock.nightGameSeconds)
        var carry = (ctx.world.logistics.fuelCarry?[id] ?? 0) + Int64(perDay) * SimStep.gameSeconds
        let burn = Int(carry / day)
        carry -= Int64(burn) * day
        if burn > 0 {
            _ = ModuleRuntime.take(burn, from: &ctx.world.placements.items[id]!.module!.input,
                                   where: { $0.stuff == .item(fuel) })
            ctx.changes.mark(.placements)
        }
        ctx.world.logistics.fuelCarry = (ctx.world.logistics.fuelCarry ?? [:]).merging([id: carry]) { $1 }
    }
}
