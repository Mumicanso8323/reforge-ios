/// 1 日の中で連続的に進む消費と生産(§5.2、§6.2、§6.5)。
///
/// 1 日あたり R 回起きる流れは、ゲーム内時刻 t に「floor(R × t / 1日)」回まで済んでいる、と決める。
/// 区間 (from, to] に入る回だけを時刻順に適用するので、結果は進めた時刻の合計だけで決まり
/// (10 秒 ×18 回 = 180 秒 ×1 回、TEST-11)、1 日を通すと必ず R 回ちょうどになる(端数の繰り越し、TEST-03)。
/// 同じ時刻に重なった回は 井戸 → 農場 → 炭焼き → 食料の消費 → 水の消費 の順(§6.5 の順のあとに消費)。
enum Flow: Int, CaseIterable, Comparable {
    case well, farm, charcoalPit, foodConsumption, waterConsumption

    static func < (a: Flow, b: Flow) -> Bool { a.rawValue < b.rawValue }

    /// 1 日あたり何回起きるか。
    func perDay(_ s: GameState, _ b: Balance) -> Int {
        switch self {
        case .well: s.has(ID.well) ? b.wellWaterPerDay : 0
        case .farm: s.has(ID.simpleFarm) ? b.farmCyclesPerDay : 0
        case .charcoalPit: s.has(ID.charcoalPit) ? b.charcoalPitCyclesPerDay : 0
        case .foodConsumption: s.population * b.foodPerPersonPerDay
        case .waterConsumption: s.population * b.waterPerPersonPerDay
        }
    }
}

public enum DayFlow {
    /// その日の進み具合を from から to(ゲーム内秒)まで進める。
    static func advance(_ s: GameState, to target: Int, gameSecondsPerDay g: Int, balance b: Balance) -> GameState {
        var s = s
        let from = s.dayProgressGameSeconds
        guard target > from, g > 0 else { return s }

        var events: [(time: Int, flow: Flow)] = []
        for flow in Flow.allCases {
            let r = flow.perDay(s, b)
            guard r > 0 else { continue }
            let doneBefore = r * from / g
            let doneAfter = r * target / g
            guard doneAfter > doneBefore else { continue }
            for k in (doneBefore + 1)...doneAfter {
                // k 回目が起きる時刻 = ceil(k × g / r)
                events.append(((k * g + r - 1) / r, flow))
            }
        }
        events.sort { ($0.time, $0.flow) < ($1.time, $1.flow) }

        for event in events {
            switch event.flow {
            case .well, .farm, .charcoalPit:
                ProductionResolver.runOnce(event.flow, &s, b)
            case .foodConsumption:
                SurvivalResolver.eatOnce(&s)
            case .waterConsumption:
                SurvivalResolver.drinkOnce(&s)
            }
        }
        s.dayProgressGameSeconds = target
        return s
    }
}

/// 建造物の生産(§6.5)。
public enum ProductionResolver {
    static func runOnce(_ flow: Flow, _ s: inout GameState, _ b: Balance) {
        switch flow {
        case .well:
            let got = s.add(ID.water, 1, balance: b)
            s.today.addProduced(ID.water, got)
        case .farm:
            // 水がなければ生産しない
            guard s.remove(ID.water, b.farmWaterIn) else { return }
            s.today.addConsumed(ID.water, b.farmWaterIn)
            let got = s.add(ID.food, b.farmFoodOut, balance: b)
            s.today.addProduced(ID.food, got)
        case .charcoalPit:
            guard s.remove(ID.wood, b.charcoalPitWoodIn) else { return }
            s.today.addConsumed(ID.wood, b.charcoalPitWoodIn)
            let got = s.add(ID.charcoal, b.charcoalPitCharcoalOut, balance: b)
            s.today.addProduced(ID.charcoal, got)
        case .foodConsumption, .waterConsumption:
            break
        }
    }
}

/// 消費と、飢え・渇きの日数(§6.2)。
public enum SurvivalResolver {
    /// 1 食分。食料が無ければ保存食で代える(GameState.cs TickFood と同じ)。どちらも無ければ不足。
    static func eatOnce(_ s: inout GameState) {
        if s.remove(ID.food, 1) {
            s.today.addConsumed(ID.food, 1)
        } else if s.remove(ID.ration, 1) {
            s.today.addConsumed(ID.ration, 1)
        } else {
            s.today.foodShort = true
        }
    }

    static func drinkOnce(_ s: inout GameState) {
        if s.remove(ID.water, 1) {
            s.today.addConsumed(ID.water, 1)
        } else {
            s.today.waterShort = true
        }
    }

    /// 1 日の終わり。足りない瞬間があった日が続いた日数を数える(足りた日で 0 に戻る)。
    static func closeDay(_ s: inout GameState) {
        s.daysWithoutFood = s.today.foodShort ? s.daysWithoutFood + 1 : 0
        s.daysWithoutWater = s.today.waterShort ? s.daysWithoutWater + 1 : 0
    }

    /// 倒れる条件を満たしたか。水のほうが先に効く。
    public static func failure(_ s: GameState, _ b: Balance) -> FailureReason? {
        if s.daysWithoutWater >= b.dehydrationDays { return .dehydration }
        if s.daysWithoutFood >= b.starvationDays { return .starvation }
        return nil
    }
}

/// 勝利(§4.3)。朝にだけ判定する。
public enum Victory {
    public static func check(_ s: GameState, _ b: Balance) -> Bool {
        !s.hasWon && s.day >= b.victoryDay && b.victoryBuildings.allSatisfy { s.has($0) }
    }
}
