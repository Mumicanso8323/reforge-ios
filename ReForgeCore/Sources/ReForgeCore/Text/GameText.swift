/// プレイヤーが目にする文言のうち、ゲームの状態から組み立てるもの(日誌・警告・理由・結果)。
/// 文言は Perception-Truth の Era 1 の認識に従う(REQ-05)。英語の ID は出さない。
/// 画面の固定文言はアプリ側の Localizable.xcstrings にある。
public struct GameText: Sendable {
    public let content: ContentDB
    public let balance: Balance

    public init(content: ContentDB, balance: Balance) {
        self.content = content
        self.balance = balance
    }

    /// 減る量に使う記号(§7 の表記「食料 −3」)。
    static let minus = "\u{2212}"

    // MARK: 共通

    public func dayLabel(_ day: Int) -> String { "\(day) 日目" }

    public func actionsLabel(_ s: GameState) -> String { "残り行動 \(s.actionPointsLeft)/\(s.actionBudget)" }

    public func name(_ item: ItemID) -> String { content.itemName(item) }

    func amounts(_ list: [ItemAmount], sign: String = "+", separator: String = " ") -> String {
        list.map { "\(name($0.item)) \(sign)\($0.quantity)" }.joined(separator: separator)
    }

    func plain(_ list: [ItemAmount], separator: String = " + ") -> String {
        list.map { "\(name($0.item)) \($0.quantity)" }.joined(separator: separator)
    }

    /// 在庫カードの数量(上限があれば「25/60」)。
    public func stockLabel(_ item: ItemID, in s: GameState) -> String {
        if let cap = s.cap(for: item, balance: balance) { return "\(s.quantity(item))/\(cap)" }
        return "\(s.quantity(item))"
    }

    // MARK: 採取(S2)

    public func gatherName(_ kind: GatherKind) -> String {
        switch kind {
        case .food: "食料採取"
        case .water: "水汲み"
        case .wood: "伐採"
        case .stone: "採石"
        case .ore: "採掘"
        case .scavenge: "残骸漁り"
        }
    }

    /// 結果の見込み。
    public func gatherPreview(_ kind: GatherKind, in s: GameState) -> String {
        let b = balance
        switch kind {
        case .food: return "\(name(ID.food)) +\(b.gatherFood + (s.hasFire ? b.gatherFoodCampfireBonus : 0))"
        case .water: return "\(name(ID.water)) +\(b.gatherWater)"
        case .wood: return "\(name(ID.wood)) +\(b.chopWood)"
        case .stone: return "\(name(ID.stone)) +\(b.quarryStone)"
        case .ore: return "\(name(ID.ironOre)) +\(b.mineOre) \(name(ID.coal)) +\(b.mineCoal)"
        case .scavenge:
            let hi = b.scavengeRationMin + b.scavengeRationSpread - 1
            return "\(name(ID.ration)) +\(b.scavengeRationMin)〜\(hi) (あと \(s.scavengeRemaining) 回)"
        }
    }

    // MARK: 製作・建造(S3・S4)

    /// 「鉄鉱石 1 + 石炭 1(または木炭 1) → 鉄インゴット 1」
    public func recipeFormula(_ r: RecipeDef) -> String {
        let ins = r.inputs.map { input -> String in
            let first = "\(name(input.options[0].item)) \(input.options[0].quantity)"
            let rest = input.options.dropFirst().map { "または\(name($0.item)) \($0.quantity)" }
            return rest.isEmpty ? first : "\(first)(\(rest.joined(separator: "、")))"
        }
        return "\(ins.joined(separator: " + ")) → \(name(r.output.item)) \(r.output.quantity)"
    }

    public func costLabel(_ bp: BlueprintDef) -> String { plain(bp.cost) }

    // MARK: 拒否の理由

    public func message(for error: ActionError) -> String {
        switch error {
        case .notAllowed(let phase):
            switch phase {
            case .night, .dusk: return "暗くて外には出られない"
            case .day, .dawn: return "いまはできません"
            }
        case .noActionPoints: return "今日はもう動けません。休みましょう"
        case let .insufficient(items, have, need):
            return "\(items.map(name).joined(separator: "か"))が足りません(\(have)/\(need))"
        case .needsBuilding(let ids):
            return "\(ids.map(content.buildingName).joined(separator: "か"))が必要です"
        case .alreadyBuilt: return "建設済み"
        case .scavengeExhausted: return "もう漁れるものはありません"
        case .noFireAtNight: return "火がなければ夜は何もできない"
        case .gameNotActive: return "いまは行動できません"
        case .invalidQuantity: return "数が正しくありません"
        case .unknown: return "その作業はできません"
        }
    }

    // MARK: 警告帯(S1)

    public enum WarningLevel: Sendable { case caution, danger }

    public struct Warning: Equatable, Sendable {
        public let level: WarningLevel
        public let text: String
    }

    public func warnings(_ s: GameState) -> [Warning] {
        var out: [Warning] = []
        let foodTotal = s.quantity(ID.food) + s.quantity(ID.ration)
        let foodPerDay = s.population * balance.foodPerPersonPerDay
        if foodTotal == 0 {
            let left = max(1, balance.starvationDays - s.daysWithoutFood)
            out.append(Warning(level: .danger, text: "\(name(ID.food))が尽きています(あと \(left) 日で餓死)"))
        } else if foodTotal < foodPerDay * balance.lowStockWarningDays {
            out.append(Warning(level: .caution, text: "\(name(ID.food))が \(days(foodTotal, perDay: foodPerDay)) 日分しかありません"))
        }
        let water = s.quantity(ID.water)
        let waterPerDay = s.population * balance.waterPerPersonPerDay
        if water == 0 {
            let left = max(1, balance.dehydrationDays - s.daysWithoutWater)
            out.append(Warning(level: .danger, text: "\(name(ID.water))が尽きています(あと \(left) 日で脱水)"))
        } else if water < waterPerDay * balance.lowStockWarningDays {
            out.append(Warning(level: .caution, text: "\(name(ID.water))が \(days(water, perDay: waterPerDay)) 日分しかありません"))
        }
        return out
    }

    /// 小数 1 桁(切り捨て)。
    func days(_ amount: Int, perDay: Int) -> String {
        guard perDay > 0 else { return "0" }
        let tenths = amount * 10 / perDay
        return "\(tenths / 10).\(tenths % 10)"
    }

    // MARK: 夜明けの結果(「寝る」の結果シートと日誌の集計行)

    public func dawnLines(_ r: DawnReport) -> [String] {
        let order = content.items.map(\.id)
        func sorted(_ d: [ItemID: Int]) -> [ItemAmount] {
            order.compactMap { id in d[id].map { ItemAmount(id, $0) } }
        }
        let consumed = sorted(r.tally.consumed)
        let produced = sorted(r.tally.produced)
        var lines = [
            "消費: " + (consumed.isEmpty ? "なし" : amounts(consumed, sign: Self.minus)),
            "生産: " + (produced.isEmpty ? "なし" : amounts(produced)),
        ]
        if r.tally.foodShort { lines.append("\(name(ID.food))が足りなかった") }
        if r.tally.waterShort { lines.append("\(name(ID.water))が足りなかった") }
        return lines
    }

    // MARK: 日誌(S7)

    public func journal(_ e: LogEntry) -> String {
        switch e.event {
        case .newGame:
            return "\(balance.protagonistName)たち \(1 + balance.initialCompanions.count) 人で、拠点を立て直しはじめた"
        case let .gathered(kind, gains, left):
            return gatheredLine(kind, gains, left)
        case let .crafted(id, times, output):
            let r = content.recipe(id)
            let verb = r?.journal ?? content.recipeName(id)
            let count = times > 1 ? "(\(times) 回)" : ""
            return "\(verb)\(count)。\(name(output.item)) +\(output.quantity)"
        case .built(let id):
            return "\(content.buildingName(id))を建てた"
        case .restedDay:
            return "今日は体を休めた"
        case .dawn(let r):
            return "長い夜が明けた。" + dawnLines(r).joined(separator: " / ")
        case .victory:
            return "拠点が自立した"
        case .gameOver(let reason):
            return failureReasonText(reason)
        case .rewound(let carried):
            let tail = carried.isEmpty ? "" : "。持ち越した物: " + plain(carried, separator: "、")
            return "記憶を頼りに、1 日目からやり直した" + tail
        case let .continuedWithLoss(people, items):
            var parts: [String] = []
            if !people.isEmpty { parts.append("\(people.joined(separator: "と"))が拠点を去った") }
            if !items.isEmpty { parts.append("失った物: " + amounts(items, sign: Self.minus, separator: "、")) }
            parts.append("それでも、ここから続ける")
            return parts.joined(separator: "。")
        case .loadedSavePoint(let day):
            return "\(day) 日目の記録から再開した"
        case .manualSave:
            return "ここまでを記録した"
        }
    }

    func gatheredLine(_ kind: GatherKind, _ gains: [ItemAmount], _ left: Int?) -> String {
        func q(_ item: ItemID) -> Int { gains.first { $0.item == item }?.quantity ?? 0 }
        func extra(_ item: ItemID) -> String {
            gains.contains { $0.item == item } ? "。\(name(item))も手に入った +\(q(item))" : ""
        }
        switch kind {
        case .food: return "食べられそうなものを集めた。\(name(ID.food)) +\(q(ID.food))"
        case .water: return "川から水を汲んだ。\(name(ID.water)) +\(q(ID.water))"
        case .wood: return "木を切り出した。\(name(ID.wood)) +\(q(ID.wood))" + extra(ID.plantFiber)
        case .stone: return "石を集めた。\(name(ID.stone)) +\(q(ID.stone))" + extra(ID.clay)
        case .ore: return "浅い鉱脈を掘った。\(name(ID.ironOre)) +\(q(ID.ironOre))、\(name(ID.coal)) +\(q(ID.coal))"
        case .scavenge: return "残骸の区画を漁った。\(name(ID.ration)) +\(q(ID.ration))(あと \(left ?? 0) 回)"
        }
    }

    // MARK: 結末(S9・S10)

    public func failureReasonText(_ reason: FailureReason) -> String {
        switch reason {
        case .starvation: "\(name(ID.food))が尽きて \(balance.starvationDays) 日が過ぎた"
        case .dehydration: "\(name(ID.water))が尽きて \(balance.dehydrationDays) 日が過ぎた"
        }
    }

    public func victoryBody(_ s: GameState) -> String {
        "井戸と畑と炉がそろい、\(s.population) 人は当面を生き延びられる。この先は、まだ誰も知らない。"
    }

    public func recoveryTitle(_ option: RecoveryOption) -> String {
        switch option {
        case .restart: "最初からやり直す"
        case .rewindWithMemory: "記憶を持ったまま巻き戻す"
        case .continueWithLoss: "失って、ここから続ける"
        case .loadSavePoint: "最後の記録から読み込む"
        }
    }

    /// 選択肢の下の 1 文(何が起きるか)。
    public func recoveryDetail(_ r: any FailureRecovery, failed: GameState, savePoint: GameState?) -> String {
        switch r {
        case let r as RewindWithMemoryRecovery:
            let carried = r.carried(from: failed)
            let what = carried.isEmpty ? "持ち越せる資材はない" : "資材を持ち越す(\(plain(carried, separator: "、")))"
            return "1 日目に戻る。\(what)"
        case let r as ContinueWithLossRecovery:
            let gone = r.companionsLost(failed)
            let who = gone.isEmpty ? "" : "\(gone.joined(separator: "と"))が去り、"
            return "\(who)物資の\(percentText(r.config.itemLossPercent))を失って、この朝から続ける"
        case is LoadSavePointRecovery:
            guard let sp = savePoint, sp.isActive else { return "読み込める記録がない" }
            return "\(sp.day) 日目の記録から再開する"
        default:
            switch r.option {
            case .restart: return "1 日目から、すべてを新しくはじめる"
            case .rewindWithMemory: return "1 日目に戻る"
            case .continueWithLoss: return "一部を失って、この朝から続ける"
            case .loadSavePoint: return "最後の記録から再開する"
            }
        }
    }

    func percentText(_ p: Int) -> String {
        p == 50 ? "半分" : " \(p) パーセント"
    }
}
