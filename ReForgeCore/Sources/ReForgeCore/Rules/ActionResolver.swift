/// 行動の解決(§6.3〜§6.5)。純関数: 状態と行動と乱数から新しい状態を返す。
/// 「休む」のうち日没・夜のもの(= 寝る)は Game.sleep が扱う。ここは昼の「休む」だけ。
public enum ActionResolver {
    public static func apply(_ s: GameState, _ action: Action, rng: inout SeededRandom,
                             content: ContentDB, timeModel: any TimeModel) -> Result<GameState, ActionError> {
        let b = timeModel.balance
        guard s.isActive else { return .failure(.gameNotActive) }
        guard timeModel.isAllowed(action, in: s.phase) else { return .failure(.notAllowed(s.phase)) }

        var s = s
        switch action {
        case .rest:
            guard s.phase == .day else { return .failure(.notAllowed(s.phase)) }
            s.actionPointsLeft = 0
            s.phase = .dusk
            s.appendLog(.restedDay, limit: b.logLimit)
            return .success(s)

        case .gather(let kind):
            guard s.actionPointsLeft >= 1 else { return .failure(.noActionPoints) }
            if kind == .scavenge, s.scavengeRemaining <= 0 { return .failure(.scavengeExhausted) }
            s.actionPointsLeft -= 1
            var gains: [ItemAmount] = []
            func gain(_ item: ItemID, _ n: Int) {
                gains.append(ItemAmount(item, s.add(item, n, balance: b)))
            }
            switch kind {
            case .food:
                gain(ID.food, b.gatherFood + (s.hasFire ? b.gatherFoodCampfireBonus : 0))
            case .water:
                gain(ID.water, b.gatherWater)
            case .wood:
                gain(ID.wood, b.chopWood)
                if rng.chance(percent: b.chopFiberChancePercent) { gain(ID.plantFiber, 1) }
            case .stone:
                gain(ID.stone, b.quarryStone)
                if rng.chance(percent: b.quarryClayChancePercent) { gain(ID.clay, 1) }
            case .ore:
                gain(ID.ironOre, b.mineOre)
                gain(ID.coal, b.mineCoal)
            case .scavenge:
                s.scavengeRemaining -= 1
                gain(ID.ration, b.scavengeRationMin + rng.int(below: b.scavengeRationSpread))
            }
            s.appendLog(.gathered(kind, gains: gains, scavengeLeft: kind == .scavenge ? s.scavengeRemaining : nil),
                        limit: b.logLimit)
            return .success(s)

        case let .craft(id, times):
            guard let recipe = content.recipe(id) else { return .failure(.unknown) }
            guard times >= 1 else { return .failure(.invalidQuantity) }
            // 夜の作業は火のそばだけ(焚き火台が無い夜は何もできない)
            if s.phase == .night, !s.hasFire { return .failure(.noFireAtNight) }
            guard s.actionPointsLeft >= times else { return .failure(.noActionPoints) }
            if !recipe.stations.isEmpty, !recipe.stations.contains(where: { s.has($0) }) {
                return .failure(.needsBuilding(recipe.stations))
            }
            if let missing = Crafting.shortage(recipe, times: times, in: s) { return .failure(missing) }
            for _ in 0..<times { Crafting.consumeOnce(recipe, &s) }
            let made = s.add(recipe.output.item, recipe.output.quantity * times, balance: b)
            s.actionPointsLeft -= times
            s.appendLog(.crafted(id, times: times, output: ItemAmount(recipe.output.item, made)), limit: b.logLimit)
            return .success(s)

        case .build(let id):
            guard let bp = content.blueprint(id) else { return .failure(.unknown) }
            guard s.actionPointsLeft >= 1 else { return .failure(.noActionPoints) }
            guard !s.has(id) else { return .failure(.alreadyBuilt(id)) }
            for c in bp.cost where s.quantity(c.item) < c.quantity {
                return .failure(.insufficient([c.item], have: s.quantity(c.item), need: c.quantity))
            }
            for c in bp.cost { s.remove(c.item, c.quantity) }
            s.buildings.append(Building(id: id, builtOnDay: s.day))
            s.actionPointsLeft -= 1
            s.appendLog(.built(id), limit: b.logLimit)
            return .success(s)
        }
    }
}

/// 製作の材料計算。入力枠ごとに候補の先頭から使う(鉄の製錬は 石炭 → 木炭 の順)。
public enum Crafting {
    /// 材料だけで見て何回作れるか(行動ポイントは見ない)。
    public static func maxTimes(_ r: RecipeDef, in s: GameState, limit: Int = 999) -> Int {
        var copy = s
        var n = 0
        while n < limit, canConsumeOnce(r, copy) {
            consumeOnce(r, &copy)
            n += 1
        }
        return n
    }

    /// times 回作るのに足りない材料。足りていれば nil。
    public static func shortage(_ r: RecipeDef, times: Int, in s: GameState) -> ActionError? {
        var copy = s
        for done in 0..<times {
            for input in r.inputs where !input.options.contains(where: { copy.quantity($0.item) >= $0.quantity }) {
                let items = input.options.map(\.item)
                let have = input.options.map { s.quantity($0.item) }.reduce(0, +)
                let per = input.options[0].quantity
                return .insufficient(items, have: have, need: per * max(times, done + 1))
            }
            consumeOnce(r, &copy)
        }
        return nil
    }

    static func canConsumeOnce(_ r: RecipeDef, _ s: GameState) -> Bool {
        var copy = s
        for input in r.inputs {
            guard let opt = input.options.first(where: { copy.quantity($0.item) >= $0.quantity }) else { return false }
            copy.remove(opt.item, opt.quantity)
        }
        return true
    }

    static func consumeOnce(_ r: RecipeDef, _ s: inout GameState) {
        for input in r.inputs {
            if let opt = input.options.first(where: { s.quantity($0.item) >= $0.quantity }) {
                s.remove(opt.item, opt.quantity)
            }
        }
    }
}
