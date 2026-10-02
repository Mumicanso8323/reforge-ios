import RFContent
import RFKernel
import RFWorld

/// 炉の熱(序盤の設計 §3.3・W-03・P-04)。持ち主: U22
///
/// 炉は火床(ModuleDef.hearth)に furnace を持つモジュール。熱は HearthState.heat(℃ × 1000)。
/// - 予熱(HearthOp.preheat): 予熱の燃料を払い、preheatSeconds かけて workTemp まで上がる。ノアの手は空く。
/// - workTemp 以上の間: 入口の燃料を時間で使い(burnPerHour)、熱を燃料の上限まで保つ。夜も同じ。
/// - 燃料が無い: 1 時間に coolPerHour 下がる。workTemp を切ったら止まり(理由 furnaceCold)、予熱し直し。
/// 1 ステップの刻みが違っても(昼・寝るの一括)、同じ時間なら同じ熱になるよう、秒の単位で整数に足し引きする。
public enum FurnaceHeat {
    /// 止まった理由(文言の ID)。
    public static let furnaceCold: TextID = "reason.production.furnace_cold"
    public static let notFurnace: TextID = "reason.hearth.not_furnace"
    public static let alreadyHot: TextID = "reason.hearth.already_hot"
    public static let noPreheatFuel: TextID = "reason.hearth.no_preheat_fuel"

    /// 炉の熱の定義(炉でなければ nil)。
    public static func def(_ p: Placement, _ c: ContentDB) -> FurnaceHeatDef? {
        guard case .module(let k) = p.kind else { return nil }
        return c.modules[k]?.hearth?.furnace
    }

    /// 今の温度(℃)。
    public static func temperature(_ p: Placement, _ c: ContentDB) -> Int? {
        guard let f = def(p, c) else { return nil }
        return (p.module?.hearth?.heat ?? f.ambient * 1000) / 1000
    }

    /// 処理が進む熱か。炉でなければ true(熱を見ない)。
    public static func isHot(_ p: Placement, _ c: ContentDB) -> Bool {
        guard let f = def(p, c) else { return true }
        return (p.module?.hearth?.heat ?? 0) >= f.work * 1000 && (p.module?.hearth?.preheatLeft ?? 0) <= 0
    }

    /// 燃料として火床で燃える物(RuleBook の燃料の条件を、入口の 1 単位ごとの数ではなく火床で満たす物)。
    public static func fuels(_ p: Placement, _ c: ContentDB) -> Set<ItemID> {
        guard let f = def(p, c) else { return [] }
        return Set(f.burn.keys).union(f.preheatCost.keys).union(f.maxTempByFuel?.keys.map { $0 } ?? [])
    }

    /// 熱い炉の灯りの半径(炉でなければ nil)。
    public static func lightRadius(_ p: Placement, _ c: ContentDB) -> Int? {
        guard let f = def(p, c) else { return nil }
        return isHot(p, c) ? f.light : 0
    }

    /// 予熱を始める。予熱の燃料は炉の入口から、足りなければ拠点の蓄えから払う。
    public static func preheat(_ id: EntityID, _ ctx: inout StepContext) -> CommandResult {
        guard let p = ctx.world.placements.items[id], let f = def(p, ctx.content) else {
            return .rejected(Rejection(notFurnace))
        }
        var s = p.module?.hearth ?? HearthState()
        if (s.preheatLeft ?? 0) > 0 || (s.heat ?? 0) >= f.work * 1000 { return .rejected(Rejection(alreadyHot)) }
        // 払えるか先に確かめる
        for (item, n) in f.preheatCost.sorted(by: { $0.key < $1.key }) {
            let have = (p.module?.inputCount(item) ?? 0) + ctx.world.inventory.quantity(item, in: .base)
            if have < n { return .rejected(Rejection(noPreheatFuel, detail: ["item": .string(item.rawValue)])) }
        }
        for (item, n) in f.preheatCost.sorted(by: { $0.key < $1.key }) {
            let fromInput = min(n, p.module?.inputCount(item) ?? 0)
            if fromInput > 0 {
                _ = ModuleRuntime.take(fromInput, from: &ctx.world.placements.items[id]!.module!.input,
                                       where: { $0.stuff == .item(item) })
            }
            if n > fromInput {
                _ = ctx.takeStock(n - fromInput, from: .base, where: { $0.stuff == .item(item) && $0.unique == nil })
            }
        }
        s.heat = s.heat ?? f.ambient * 1000
        s.preheatLeft = f.preheat
        s.lit = true
        ctx.world.placements.items[id]?.module?.hearth = s
        ctx.changes.mark([.placements, .inventory])
        return .done
    }

    /// seconds だけ進める(RFProduction が毎ステップ呼ぶ)。
    public static func advance(_ id: EntityID, seconds: Int, _ ctx: inout StepContext) {
        guard let p = ctx.world.placements.items[id], let f = def(p, ctx.content), p.module != nil else { return }
        let before = p.module?.hearth ?? HearthState()
        var s = before
        var heat = s.heat ?? f.ambient * 1000
        let work = f.work * 1000
        var left = seconds
        // 予熱: 残りの時間で workTemp まで線形に上げる
        if let pre = s.preheatLeft, pre > 0 {
            let k = min(pre, left)
            heat += max(0, work - heat) * k / pre
            s.preheatLeft = pre - k
            left -= k
            if s.preheatLeft == 0 {
                s.preheatLeft = nil
                heat = max(heat, work)
            }
        }
        // 熱を保つ(熱い間だけ燃料を使う)・冷める
        if left > 0 {
            let fuel = heat >= work ? pickFuel(p, f, s.fuelItem) : nil
            if let fuel {
                s.fuelItem = fuel
                heat = max(heat, min(f.cap(fuel) * 1000, f.max * 1000))
                if f.cap(fuel) * 1000 < work { heat = f.cap(fuel) * 1000 }
                var carry = (s.burnCarry ?? 0) + (f.burn[fuel] ?? 0) * 1000 * left / 3600
                while carry >= 1_000_000 {
                    guard (ctx.world.placements.items[id]?.module?.inputCount(fuel) ?? 0) > 0 else { break }
                    _ = ModuleRuntime.take(1, from: &ctx.world.placements.items[id]!.module!.input,
                                           where: { $0.stuff == .item(fuel) })
                    carry -= 1_000_000
                    ctx.changes.mark(.placements)
                }
                s.burnCarry = carry
            } else {
                heat = max(f.ambient * 1000, heat - f.cool * 1000 * left / 3600)
                s.fuelItem = nil
            }
        }
        s.heat = heat
        s.lit = heat >= work || (s.preheatLeft ?? 0) > 0
        guard s != before else { return }
        ctx.world.placements.items[id]?.module?.hearth = s
        if ((before.heat ?? 0) >= work) != (heat >= work) {
            ctx.changes.mark(.placements)
            ctx.changes.markTile(p.at, .placements)
        }
    }

    /// 入口にある燃料のうち、熱を保てるもの(いま燃えている物を先に、次に ID の順)。
    static func pickFuel(_ p: Placement, _ f: FurnaceHeatDef, _ current: ItemID?) -> ItemID? {
        guard let m = p.module else { return nil }
        let order = (current.map { [$0] } ?? []) + f.burn.keys.sorted()
        return order.first { f.burn[$0] != nil && m.inputCount($0) > 0 }
    }
}
