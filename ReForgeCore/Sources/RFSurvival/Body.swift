import RFContent
import RFKernel
import RFRules
import RFWorld

/// 人の体: 食事・水・精神力・状態と回復・作業の速さ。規則は全員に共通(REQ-S5)。
enum Body {
    static let maxValue: Int64 = 100_000

    // MARK: - ステップ
    //
    // 寝て夜を飛ばすときも回るので軽く保つ(目標: 本物のコンテンツで release 1 日 50ms 以内。
    // Tests/RFSurvivalTests/SurvivalPerformanceTests)。体と数値は毎ステップではなく区切り(SurvivalDef.tickSeconds、
    // 既定 5 ゲーム分)ごとに、その間の秒をまとめて端数つきで進める。区切りはゲーム時刻で決まるので、刻みや寝るによらず一致する。
    // 人と置いた物は辞書の位置から借りて読み(丸ごと写さない)、一員の並びは写しを持って出来事で引き直す。

    /// 体の値の 1 時間あたりの率(raw)。辞書を使わずに 1 ステップの計算を軽くする。
    struct PerHour {
        var health: Int64 = 0
        var stamina: Int64 = 0
        var satiety: Int64 = 0
        var hydration: Int64 = 0
        var mind: Int64 = 0

        mutating func add(_ stat: String, _ v: Int64) {
            switch stat {
            case "health": health += v
            case "stamina": stamina += v
            case "satiety": satiety += v
            case "hydration": hydration += v
            case "mind": mind += v
            default: break
            }
        }
    }

    /// 1 ステップの中で全員に共通の周り(シェルターのマス・体に効く範囲の効果)。人ごとに引き直さない。
    struct Surroundings {
        struct BodyAura {
            var center: WorldPoint
            var radius: Int
            var affects: [PersonID]?
            var effects: [(stat: String, amount: Int64)]
        }

        var shelter: [WorldPoint] = []
        var auras: [BodyAura] = []

        init(_ r: SurvivalDef, items: [EntityID: Placement], structures: [StructureKindID: StructureDef],
             active: [EntityID: Aura], auraDefs: [AuraKindID: AuraDef], persons: [PersonID: PersonState], now: GameTime)
        {
            let tag = r.shelter
            var i = items.values.startIndex
            while i != items.values.endIndex {
                if case .structure(let k) = items.values[i].kind, items.values[i].status == .running,
                   structures[k]?.provides[tag] != nil
                {
                    let at = items.values[i].at
                    for f in items.values[i].footprint {
                        shelter.append(WorldPoint(at.layer, GridPoint(at.point.x + f.x, at.point.y + f.y)))
                    }
                }
                items.values.formIndex(after: &i)
            }
            guard !active.isEmpty else { return }
            // 範囲の効果は ID 順(Auras.covering と同じ順)。中心は Auras.center と同じ決め方
            for a in active.values.sorted(by: { $0.id < $1.id }) {
                guard a.strength > 0, a.until.map({ now < $0 }) ?? true, let def = auraDefs[a.kind] else { continue }
                let center: WorldPoint?
                switch a.source {
                case .point(let pt): center = pt
                case .person(let id): center = persons.index(forKey: id).flatMap { persons.values[$0].position }
                case .placement(let e): center = items.index(forKey: e).map { items.values[$0].at }
                }
                guard let c = center else { continue }
                var effects: [(stat: String, amount: Int64)] = []
                for m in def.modifiers {
                    if case .bodyPerHour(let stat, let amount) = m {
                        effects.append((stat, Int64(amount) * Int64(a.strength) / 1000))
                    }
                }
                if !effects.isEmpty { auras.append(BodyAura(center: c, radius: a.radius, affects: def.affects, effects: effects)) }
            }
        }

        func apply(at pos: WorldPoint, person p: PersonID, _ r: SurvivalDef, _ rates: inout PerHour) {
            rates.mind += Int64(shelter.contains(pos) ? r.mindShelter : r.mindOutside)
            for a in auras where a.center.layer == pos.layer && a.center.point.chebyshev(to: pos.point) <= a.radius {
                if let only = a.affects, !only.contains(p) { continue }
                for e in a.effects { rates.add(e.stat, e.amount) }
            }
        }
    }

    /// 一員の並び(people.order の順)。写しを survival.members に持ち、合流・離脱・死の出来事と夜明けで引き直す。
    /// 写しの人が一員でなくなっていたら(出来事を出さない変更)、その場で引き直す。
    static func members(_ ctx: inout StepContext) -> [PersonID] {
        let persons = ctx.world.people.persons
        if let cached = ctx.world.survival.members {
            let ok = cached.allSatisfy { id in
                guard let i = persons.index(forKey: id), case .member = persons.values[i].presence else { return false }
                return true
            }
            if ok { return cached }
        }
        var list: [PersonID] = []
        for id in ctx.world.people.order {
            if let i = persons.index(forKey: id), case .member = persons.values[i].presence { list.append(id) }
        }
        ctx.world.survival.members = list
        return list
    }

    /// 体の区切り 1 回(前の区切りから seconds 秒ぶん)。
    static func step(_ r: SurvivalDef, seconds: Int64, _ ctx: inout StepContext) {
        let daySeconds = Stats.dayLength(ctx.content.clock)
        let unit = daySeconds * 1000
        let now = ctx.world.clock.now
        let members = members(&ctx)
        var newlyHungry = false
        var newlyThirsty = false
        var foodDemand: Int64 = 0
        var waterDemand: Int64 = 0

        // 1. 食事と水(在庫を減らす・危険を引く。ここで体に状態が付くことがあるので、体の値は 2 で読み直す)
        for p in members {
            let studying = ctx.world.research.isLearning(p)
                || isStudying(p, r, ctx.world.people.persons, ctx.world.placements.items, ctx.content.structures)
            var v = ctx.world.survival.vitals[p] ?? Vitals()
            let foodRate = Int64(r.foodPerDay) * Int64(studying ? r.studyFood : 1000) / 1000
            let waterRate = Int64(r.waterPerDay)
            foodDemand += foodRate
            waterDemand += waterRate
            if meal(.food, rate: foodRate, seconds: seconds, &v.foodProgress, &v.hungrySince, &v.foodCredit, p, r, unit, now, &ctx) {
                newlyHungry = true
            }
            if meal(.water, rate: waterRate, seconds: seconds, &v.waterProgress, &v.thirstySince, &v.waterCredit, p, r, unit, now, &ctx) {
                newlyThirsty = true
            }
            ctx.world.survival.vitals[p] = v
        }

        // 2. 体の値・状態の回復・作業の速さ
        let around = Surroundings(r, items: ctx.world.placements.items, structures: ctx.content.structures,
                                  active: ctx.world.auras.active, auraDefs: ctx.content.auras,
                                  persons: ctx.world.people.persons, now: now)
        var minHungry: Int64?
        var minThirsty: Int64?
        for p in members {
            guard let pi = ctx.world.people.persons.index(forKey: p),
                  let vi = ctx.world.survival.vitals.index(forKey: p) else { continue }
            let before = ctx.world.people.persons.values[pi].body
            let position = ctx.world.people.persons.values[pi].position
            var body = before
            var v = ctx.world.survival.vitals.values[vi]
            body.satiety = Milli(raw: fullness(v.foodProgress, v.hungrySince, v.foodCredit, unit))
            body.hydration = Milli(raw: fullness(v.waterProgress, v.thirstySince, v.waterCredit, unit))

            // 1 時間あたりの増減を集めて、体の値ごとに端数つきで足す
            var rates = PerHour()
            if let pos = position { around.apply(at: pos, person: p, r, &rates) }
            if body.conditions.isEmpty {
                rates.health += Int64(r.healthRegen)
            } else {
                for (id, _) in body.conditions {
                    for (stat, amount) in r.ailment(id)?.bodyPerHour ?? [:] { rates.add(stat, Int64(amount)) }
                }
            }
            rates.stamina += Int64(r.staminaRegen)
            func advance(_ rate: Int64, _ carry: inout Int64, _ value: inout Milli) {
                guard rate != 0 else { return }
                let d = Rates.advance(&carry, perHour: rate, seconds: seconds)
                if d != 0 { value = Milli(raw: min(maxValue, max(0, value.raw + d))) }
            }
            advance(rates.health, &v.carry.health, &body.health)
            advance(rates.hydration, &v.carry.hydration, &body.hydration)
            advance(rates.mind, &v.carry.mind, &body.mind)
            advance(rates.satiety, &v.carry.satiety, &body.satiety)
            advance(rates.stamina, &v.carry.stamina, &body.stamina)

            // 状態の回復(全員に共通の速さ。BEAT-15)と、状態による作業の遅れ
            var healed = false
            var work: Int64 = 1000
            if !body.conditions.isEmpty {
                for (id, sev) in body.conditions.sorted(by: { $0.key < $1.key }) {
                    let def = r.ailment(id)
                    let rec = Int64(def?.recoveryPerDay ?? 0)
                    if rec > 0 {
                        let d = Rates.advance(&v.ailmentCarry[id, default: 0], perDay: rec, seconds: seconds,
                                              daySeconds: daySeconds)
                        let left = Int64(sev) - d
                        if left <= 0 {
                            body.conditions[id] = nil
                            v.ailmentCarry[id] = nil
                            healed = true
                            continue
                        }
                        body.conditions[id] = Int(left)
                    }
                    if let w = def?.workPermille { work = work * Int64(w) / 1000 }
                }
            }

            // 作業の速さ
            if v.hungrySince != nil { work = work * Int64(r.hungryWork) / 1000 }
            if v.thirstySince != nil { work = work * Int64(r.thirstyWork) / 1000 }
            if body.mind.raw < Int64(r.mindLow) { work = work * Int64(r.mindLowWork) / 1000 }
            if body.stamina.raw < Int64(r.staminaLow) { work = work * Int64(r.staminaLowWork) / 1000 }
            let newWork: Int? = work == 1000 ? nil : Int(work)
            if ctx.world.survival.work[p] != newWork { ctx.world.survival.work[p] = newWork }

            let hungry = v.hungrySince.map { (now - $0).seconds } ?? 0
            let thirsty = v.thirstySince.map { (now - $0).seconds } ?? 0
            minHungry = min(minHungry ?? hungry, hungry)
            minThirsty = min(minThirsty ?? thirsty, thirsty)

            ctx.world.survival.vitals.values[vi] = v
            if body != before { ctx.world.people.persons.values[pi].body = body }
            if healed { ctx.emit(.bodyChanged(person: p)) }
        }
        // 一員でない人の速さは残さない
        if !ctx.world.survival.work.isEmpty, ctx.world.survival.work.keys.contains(where: { !members.contains($0) }) {
            ctx.world.survival.work = ctx.world.survival.work.filter { members.contains($0.key) }
        }

        // 3. 拠点全体の値(餓死・脱水の判定は値で。全員が食べられずにいる長さ = 一番短い人の長さ)
        let hungryDays = (minHungry ?? 0) * 1000 / daySeconds
        let thirstyDays = (minThirsty ?? 0) * 1000 / daySeconds
        let stock = stockPortions(members, r, ctx.world.inventory.holders)
        set(&ctx, r.daysWithoutFoodStat, hungryDays)
        set(&ctx, r.daysWithoutWaterStat, thirstyDays)
        set(&ctx, r.foodDaysStat, foodDemand > 0 ? stock.food * 1_000_000 / foodDemand : 0)
        set(&ctx, r.waterDaysStat, waterDemand > 0 ? stock.water * 1_000_000 / waterDemand : 0)
        ctx.world.survival.daysWithoutFood = Int(hungryDays / 1000)
        ctx.world.survival.daysWithoutWater = Int(thirstyDays / 1000)

        if newlyHungry, let item = r.consumables.first(where: { $0.kind == .food && $0.isAuto })?.item {
            ctx.emit(.shortage(item: item))
        }
        if newlyThirsty, let item = r.consumables.first(where: { $0.kind == .water && $0.isAuto })?.item {
            ctx.emit(.shortage(item: item))
        }
        ctx.changes.mark([.people, .survival])
    }

    /// 拠点全体の値を書く(変わったときだけ書き、合計の定義の内訳なら合計も直す)。
    static func set(_ ctx: inout StepContext, _ id: StatID, _ raw: Int64) {
        if let i = ctx.world.survival.stats.index(forKey: id) {
            guard ctx.world.survival.stats.values[i].raw != raw else { return }
            ctx.world.survival.stats.values[i] = Milli(raw: raw)
        } else {
            ctx.world.survival.stats[id] = Milli(raw: raw)
        }
        let defs = ctx.content.stats
        if defs.values.contains(where: { $0.sumOf?.contains(id) == true }) {
            Stats.recomputeSums(&ctx.world.survival, defs)
        }
    }

    /// seconds 秒ぶん食事を進める。食べるべき時に食べられなかった(空腹が始まった)ら true。
    /// 空腹の始まりは、区切りの時刻でなく、食べるべきだった時刻(進みのあふれから逆算)にする。
    static func meal(_ kind: ConsumableDef.Kind, rate: Int64, seconds: Int64, _ progress: inout Int64,
                     _ since: inout GameTime?, _ credit: inout Int, _ p: PersonID, _ r: SurvivalDef, _ unit: Int64,
                     _ now: GameTime, _ ctx: inout StepContext) -> Bool
    {
        var newly = false
        progress += seconds * rate
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
                since = rate > 0 ? GameTime(seconds: now.seconds - progress / rate) : now
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
        guard let i = ctx.world.people.persons.index(forKey: p) else { return }
        add(&ctx.world.people.persons.values[i].body, stat, raw)
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

    /// 研究の建造物に付いているか(配属かいまの動作)。BEAT-15: 学ぶ時期は食料の消費が増える(全員に共通)。
    /// スキルを習っている・研究を進めた人は、呼び出し側が研究の担当の isLearning で見る(机の外でも学ぶ時期)。
    static func isStudying(_ p: PersonID, _ r: SurvivalDef, _ persons: [PersonID: PersonState],
                           _ items: [EntityID: Placement], _ structures: [StructureKindID: StructureDef]) -> Bool
    {
        guard let pi = persons.index(forKey: p) else { return false }
        var targets: (EntityID?, EntityID?) = (nil, nil)
        if case .operate(let e) = persons.values[pi].assignment { targets.0 = e }
        if case .working(let e) = persons.values[pi].activity { targets.1 = e }
        guard targets.0 != nil || targets.1 != nil else { return false }
        let tags = r.study
        for id in [targets.0, targets.1].compactMap({ $0 }) {
            guard let i = items.index(forKey: id), case .structure(let k) = items.values[i].kind,
                  items.values[i].status == .running, let provides = structures[k]?.provides
            else { continue }
            if tags.contains(where: { provides[$0] != nil }) { return true }
        }
        return false
    }

    /// 自動で減らす物の蓄え(何人分か)。拠点の蓄えと一員の持ち物を数える。食べ物と水を 1 回でなめる。
    static func stockPortions(_ members: [PersonID], _ r: SurvivalDef, _ holders: [HolderID: [StockEntry]])
        -> (food: Int64, water: Int64)
    {
        var food: Int64 = 0
        var water: Int64 = 0
        func count(_ h: HolderID) {
            guard let hi = holders.index(forKey: h) else { return }
            for e in holders.values[hi] where e.unique == nil {
                guard case .item(let item) = e.stuff else { continue }
                for c in r.consumables where c.item == item && c.isAuto {
                    let n = Int64(e.quantity) * Int64(max(1, c.portions ?? 1))
                    if c.kind == .food { food += n } else { water += n }
                    break
                }
            }
        }
        count(.base)
        for p in members { count(.person(p)) }
        return (food, water)
    }
}
