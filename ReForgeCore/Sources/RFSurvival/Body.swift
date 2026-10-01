import RFContent
import RFKernel
import RFRules
import RFWorld

/// 人の体: 食事・水・精神力・状態と回復・作業の速さ。規則は全員に共通(REQ-S5)。
enum Body {
    static let maxValue: Int64 = 100_000

    // MARK: - ステップ

    static func step(_ r: SurvivalDef, _ ctx: inout StepContext) {
        let daySeconds = Stats.dayLength(ctx.content)
        let unit = daySeconds * 1000
        let seconds = SimStep.gameSeconds
        let now = ctx.world.clock.now
        let members = ctx.world.people.members.filter { ctx.world.people[$0]?.presence.isAlive == true }
        var newlyHungry = false
        var newlyThirsty = false
        var foodDemand: Int64 = 0
        var waterDemand: Int64 = 0

        // 1. 食事と水(在庫を減らす・危険を引く。ここで体に状態が付くことがあるので、体の値は 2 で読み直す)
        for p in members {
            guard let ps = ctx.world.people[p] else { continue }
            var v = ctx.world.survival.vitals[p] ?? Vitals()
            let foodRate = Int64(r.foodPerDay) * Int64(isStudying(ps, r, ctx) ? r.studyFood : 1000) / 1000
            let waterRate = Int64(r.waterPerDay)
            foodDemand += foodRate
            waterDemand += waterRate
            if meal(.food, rate: foodRate, &v.foodProgress, &v.hungrySince, &v.foodCredit, p, r, unit, now, &ctx) {
                newlyHungry = true
            }
            if meal(.water, rate: waterRate, &v.waterProgress, &v.thirstySince, &v.waterCredit, p, r, unit, now, &ctx) {
                newlyThirsty = true
            }
            ctx.world.survival.vitals[p] = v
        }

        // 2. 体の値・状態の回復・作業の速さ
        var minHungry: Int64?
        var minThirsty: Int64?
        for p in members {
            guard var ps = ctx.world.people[p], var v = ctx.world.survival.vitals[p] else { continue }
            ps.body.satiety = Milli(raw: fullness(v.foodProgress, v.hungrySince, v.foodCredit, unit))
            ps.body.hydration = Milli(raw: fullness(v.waterProgress, v.thirstySince, v.waterCredit, unit))

            // 1 時間あたりの増減を集める
            var perHour: [String: Int64] = [:]
            if let pos = ps.position {
                perHour["mind", default: 0] += Int64(inShelter(pos, r, ctx) ? r.mindShelter : r.mindOutside)
                for (m, strength, aura) in Auras.modifiers(at: pos, in: ctx.world, content: ctx.content) {
                    if let only = ctx.content.auras[aura.kind]?.affects, !only.contains(p) { continue }
                    if case .bodyPerHour(let stat, let amount) = m {
                        perHour[stat, default: 0] += Int64(amount) * Int64(strength) / 1000
                    }
                }
            }
            for (id, _) in ps.body.conditions {
                for (stat, amount) in r.ailment(id)?.bodyPerHour ?? [:] { perHour[stat, default: 0] += Int64(amount) }
            }
            if ps.body.conditions.isEmpty { perHour["health", default: 0] += Int64(r.healthRegen) }
            for (stat, rate) in perHour.sorted(by: { $0.key < $1.key }) where rate != 0 {
                let d = Rates.advance(&v.carry[stat, default: 0], perHour: rate, seconds: seconds)
                if d != 0 { add(&ps.body, stat, d) }
            }

            // 状態の回復(全員に共通の速さ。BEAT-15)
            var healed = false
            for (id, sev) in ps.body.conditions.sorted(by: { $0.key < $1.key }) {
                let rec = Int64(r.ailment(id)?.recoveryPerDay ?? 0)
                guard rec > 0 else { continue }
                let key = "ailment:\(id.rawValue)"
                let d = Rates.advance(&v.carry[key, default: 0], perDay: rec, seconds: seconds, daySeconds: daySeconds)
                let left = Int64(sev) - d
                if left <= 0 {
                    ps.body.conditions[id] = nil
                    v.carry[key] = nil
                    healed = true
                } else {
                    ps.body.conditions[id] = Int(left)
                }
            }

            // 作業の速さ
            var work: Int64 = 1000
            if v.hungrySince != nil { work = work * Int64(r.hungryWork) / 1000 }
            if v.thirstySince != nil { work = work * Int64(r.thirstyWork) / 1000 }
            for (id, _) in ps.body.conditions.sorted(by: { $0.key < $1.key }) {
                if let w = r.ailment(id)?.workPermille { work = work * Int64(w) / 1000 }
            }
            if ps.body.mind.raw < Int64(r.mindLow) { work = work * Int64(r.mindLowWork) / 1000 }
            ctx.world.survival.work[p] = work == 1000 ? nil : Int(work)

            let hungry = v.hungrySince.map { (now - $0).seconds } ?? 0
            let thirsty = v.thirstySince.map { (now - $0).seconds } ?? 0
            minHungry = min(minHungry ?? hungry, hungry)
            minThirsty = min(minThirsty ?? thirsty, thirsty)

            ctx.world.survival.vitals[p] = v
            ctx.world.people[p] = ps
            if healed { ctx.emit(.bodyChanged(person: p)) }
        }
        // 一員でない人の速さは残さない
        let memberSet = Set(members)
        ctx.world.survival.work = ctx.world.survival.work.filter { memberSet.contains($0.key) }

        // 3. 拠点全体の値(餓死・脱水の判定は値で。全員が食べられずにいる長さ = 一番短い人の長さ)
        let s = ctx.world.survival
        var stats = s.stats
        let hungryDays = (minHungry ?? 0) * 1000 / daySeconds
        let thirstyDays = (minThirsty ?? 0) * 1000 / daySeconds
        stats[r.daysWithoutFoodStat] = Milli(raw: hungryDays)
        stats[r.daysWithoutWaterStat] = Milli(raw: thirstyDays)
        stats[r.foodDaysStat] = Milli(raw: stockDays(.food, demand: foodDemand, members, r, ctx))
        stats[r.waterDaysStat] = Milli(raw: stockDays(.water, demand: waterDemand, members, r, ctx))
        ctx.world.survival.stats = stats
        ctx.world.survival.daysWithoutFood = Int(hungryDays / 1000)
        ctx.world.survival.daysWithoutWater = Int(thirstyDays / 1000)
        Stats.recomputeSums(&ctx.world.survival, ctx.content)

        if newlyHungry, let item = r.consumables.first(where: { $0.kind == .food && $0.isAuto })?.item {
            ctx.emit(.shortage(item: item))
        }
        if newlyThirsty, let item = r.consumables.first(where: { $0.kind == .water && $0.isAuto })?.item {
            ctx.emit(.shortage(item: item))
        }
        ctx.changes.mark([.people, .survival])
    }

    /// 1 ステップぶん食事を進める。食べるべき時に食べられなかった(空腹が始まった)ら true。
    static func meal(_ kind: ConsumableDef.Kind, rate: Int64, _ progress: inout Int64, _ since: inout GameTime?,
                     _ credit: inout Int, _ p: PersonID, _ r: SurvivalDef, _ unit: Int64, _ now: GameTime,
                     _ ctx: inout StepContext) -> Bool
    {
        var newly = false
        progress += SimStep.gameSeconds * rate
        while progress >= unit {
            progress -= unit
            if credit > 0 {
                credit -= 1
                continue
            }
            let got = eat(kind, p, r, &ctx)
            if got > 0 {
                since = nil
                credit = min(1, credit + got - 1)
            } else if since == nil {
                since = now
                newly = true
            }
        }
        // 食べられずにいる間は、物が手に入ったらすぐ食べる(次の 1 食はそこから 1 日後)
        if since != nil, !newly {
            let got = eat(kind, p, r, &ctx)
            if got > 0 {
                since = nil
                progress = 0
                credit = min(1, credit + got - 1)
            }
        }
        return newly
    }

    /// 自動で減らす物を 1 個口にする(本人の持ち物 → 拠点の蓄え)。何人分だったかを返す(0 = 無かった)。
    static func eat(_ kind: ConsumableDef.Kind, _ p: PersonID, _ r: SurvivalDef, _ ctx: inout StepContext) -> Int {
        for c in r.consumables where c.kind == kind && c.isAuto {
            for h in [HolderID.person(p), .base] {
                let stuff = Stuff.item(c.item)
                if let took = ctx.takeStock(1, from: h, where: { $0.stuff == stuff && $0.unique == nil }) {
                    risk(p, c, r, inputs: took.keys.sorted(), &ctx)
                    return max(1, c.portions ?? 1)
                }
            }
        }
        return 0
    }

    // MARK: - プレイヤーが選んで口にする

    static func consume(person: PersonID, stock: StockSelector, _ r: SurvivalDef, _ ctx: inout StepContext)
        -> CommandResult
    {
        guard let ps = ctx.world.people[person], ps.presence.isMember else {
            return .rejected(Rejection("reason.survival.no_person"))
        }
        guard case .item(let item) = stock.stuff, let c = r.consumable(item) else {
            return .rejected(Rejection("reason.survival.not_consumable"))
        }
        var v = ctx.world.survival.vitals[person] ?? Vitals()
        let lacking = c.kind == .food ? v.hungrySince != nil : v.thirstySince != nil
        let credit = c.kind == .food ? v.foodCredit : v.waterCredit
        if !lacking, credit >= 1 { return .rejected(Rejection("reason.survival.full")) }
        guard let took = ctx.takeStock(1, from: stock.holder, where: { $0.stuff == stock.stuff && $0.unique == stock.unique })
        else { return .rejected(Rejection("reason.survival.none")) }
        let rec = ctx.record(.consumed, .item(item), actor: person, place: ps.position, inputs: took.keys.sorted())
        var left = max(1, c.portions ?? 1)
        switch c.kind {
        case .food:
            if v.hungrySince != nil { v.hungrySince = nil; v.foodProgress = 0; left -= 1 }
            v.foodCredit = min(1, v.foodCredit + left)
        case .water:
            if v.thirstySince != nil { v.thirstySince = nil; v.waterProgress = 0; left -= 1 }
            v.waterCredit = min(1, v.waterCredit + left)
        }
        ctx.world.survival.vitals[person] = v
        risk(person, c, r, inputs: [rec], &ctx)
        ctx.emit(.bodyChanged(person: person))
        ctx.changes.mark([.people, .survival])
        return .done
    }

    /// 口にした物の危険を引く(生存の乱数の流れ)。当たれば状態が付き、来歴に「中毒した」が残る(試食で覚える道の数え方)。
    static func risk(_ p: PersonID, _ c: ConsumableDef, _ r: SurvivalDef, inputs: [ProvenanceID],
                     _ ctx: inout StepContext)
    {
        guard let risk = c.risk, risk.basisPoints > 0 else { return }
        let hit = ctx.random(.survival) { $0.chance(basisPoints: risk.basisPoints) }
        guard hit else { return }
        var detail: [String: Value] = [:]
        if let a = risk.ailment { detail["ailment"] = .string(a.rawValue) }
        ctx.record(.wasInjured, .item(c.item), actor: p, place: ctx.world.people[p]?.position, inputs: inputs,
                   detail: detail)
        if let a = risk.ailment { afflict(p, a, risk.severity ?? 1, r, &ctx) }
        for (stat, amount) in (risk.body ?? [:]).sorted(by: { $0.key < $1.key }) {
            adjust(p, stat, Int64(amount), &ctx)
        }
        ctx.emit(.bodyChanged(person: p))
    }

    // MARK: - 状態

    static func afflict(_ p: PersonID, _ id: StatID, _ severity: Int, _ r: SurvivalDef, _ ctx: inout StepContext) {
        guard severity > 0, var ps = ctx.world.people[p] else { return }
        var v = (ps.body.conditions[id] ?? 0) + severity
        if let m = r.ailment(id)?.maxSeverity { v = min(v, m) }
        ps.body.conditions[id] = v
        ctx.world.people[p] = ps
        ctx.emit(.bodyChanged(person: p))
        ctx.changes.mark(.people)
    }

    static func adjust(_ p: PersonID, _ stat: String, _ raw: Int64, _ ctx: inout StepContext) {
        guard var ps = ctx.world.people[p] else { return }
        add(&ps.body, stat, raw)
        ctx.world.people[p] = ps
        ctx.changes.mark(.people)
    }

    // MARK: - 道具

    /// 体の値に足す(0〜100 に収める)。知らない名前は何もしない。
    static func add(_ b: inout BodyState, _ stat: String, _ raw: Int64) {
        func clamp(_ m: inout Milli) { m = Milli(raw: min(maxValue, max(0, m.raw + raw))) }
        switch stat {
        case "health": clamp(&b.health)
        case "stamina": clamp(&b.stamina)
        case "satiety": clamp(&b.satiety)
        case "hydration": clamp(&b.hydration)
        case "mind": clamp(&b.mind)
        default: break
        }
    }

    /// 満腹・水分の見える値(次の 1 食までの進みから。食べられずにいれば 0、先に口にした分があれば満タン)。
    static func fullness(_ progress: Int64, _ since: GameTime?, _ credit: Int, _ unit: Int64) -> Int64 {
        if since != nil { return 0 }
        if credit > 0 { return maxValue }
        return max(0, maxValue - maxValue * min(progress, unit) / unit)
    }

    /// シェルター(provides に shelterTag を持つ、建ち終えた建造物)の中にいるか。
    static func inShelter(_ pos: WorldPoint, _ r: SurvivalDef, _ ctx: StepContext) -> Bool {
        ctx.world.placements.at(pos).contains { id in
            guard let pl = ctx.world.placements.items[id], case .structure(let k) = pl.kind, pl.status == .running
            else { return false }
            return ctx.content.structures[k]?.provides[r.shelter] != nil
        }
    }

    /// 学んでいるか(研究の建造物に付いている)。BEAT-15: 学ぶ時期は食料の消費が増える(全員に共通)。
    static func isStudying(_ ps: PersonState, _ r: SurvivalDef, _ ctx: StepContext) -> Bool {
        var targets: [EntityID] = []
        if case .operate(let e) = ps.assignment { targets.append(e) }
        if case .working(let e) = ps.activity { targets.append(e) }
        let tags = r.study
        return targets.contains { id in
            guard let pl = ctx.world.placements.items[id], case .structure(let k) = pl.kind, pl.status == .running,
                  let provides = ctx.content.structures[k]?.provides
            else { return false }
            return tags.contains { provides[$0] != nil }
        }
    }

    /// 自動で減らす物の蓄えが何日もつか(Milli の日数)。拠点の蓄えと一員の持ち物を数える。
    static func stockDays(_ kind: ConsumableDef.Kind, demand: Int64, _ members: [PersonID], _ r: SurvivalDef,
                          _ ctx: StepContext) -> Int64
    {
        guard demand > 0 else { return 0 }
        let holders = [HolderID.base] + members.map { HolderID.person($0) }
        var portions: Int64 = 0
        for c in r.consumables where c.kind == kind && c.isAuto {
            let per = Int64(max(1, c.portions ?? 1))
            for h in holders {
                for e in ctx.world.inventory.holders[h] ?? [] where e.stuff == .item(c.item) && e.unique == nil {
                    portions += Int64(e.quantity) * per
                }
            }
        }
        return portions * 1_000_000 / demand
    }
}
