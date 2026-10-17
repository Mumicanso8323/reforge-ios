import Foundation
import ReForgeEngine
import RFRules
import RFTestSupport

/// Deterministic W-05 driver.  It deliberately models only the opening labour
/// ledger until W-13 can replace Provision and Labor with actual gathering.
struct LineBotResult: Equatable {
    struct LaborDay: Equatable {
        var assignedHours: Int = 0
        var fellingHours: Int = 0
        var woodAdded: Int = 0
    }

    var plates: [Int: Int] = [:]
    var handOre: [Int: Int] = [:]
    var lineOre: [Int: Int] = [:]
    var platesOnHandAtDawn: [Int: Int] = [:]
    var furnaceHotSeconds: [Int: Int] = [:]
    var charcoalUsed: [Int: Int] = [:]
    var provisioned: [Int: [ItemID: Int]] = [:]
    var labor: [Int: LaborDay] = [:]
    var laborShortfall: [Int: Int] = [:]
}

enum LineBotPath: String, Hashable { case A, B }

struct LineBot {
    let sim: Simulation
    var w: WorldState
    let home: GridPoint
    let ironOutcrop: GridPoint
    let ironOutcropExtractions: Int
    let ironVein: GridPoint
    let coalVein: GridPoint
    var result = LineBotResult()
    var furnaceIDs: [EntityID] = []
    var kilnIDs: [EntityID] = []
    var design: EntityID?
    var anvilIDs: [EntityID] = []
    var autoHeat = false
    /// Body gap (reported, not fixed): HaulRoute only moves items a module lists in auxPerUnit, so a coal route
    /// minehead -> furnace never carries (room(for:) == 0).  Path B emulates the hauler's daily capacity here.
    var coalMine: EntityID?
    var coalRoute: EntityID?
    var coalBudget = 0
    var coalDailyCapacity = 0
    var heatFuel = LineBotKit.charcoal

    /// These are the smallest systems that make the assigned work real: crew
    /// reaches jobs, exploration performs kiln work, base builds kilns, and
    /// production/logistics/invention run the line.  Expensive perception and
    /// event systems are intentionally absent.
    static var systems: [any SimSystem] {
        [TimeSystem(), CrewSystem(), ExplorationSystem(), ProductionSystem(), LogisticsSystem(), BaseSystem(), InventionSystem()]
    }

    init(content: ContentDB, seed: UInt64) {
        // The W-05 labour model is "four crew x eight hours".  A fresh world has no campfire or beds, so the
        // working-slot cap (INV-O10) would bench everyone; lift only that cap here and report it as a deviation.
        var content = content
        if content.crewWork != nil { content.crewWork?.fireSlots = [4, 4, 4, 4, 4] }
        sim = Simulation(content: content, systems: Self.systems)
        let factory = WorldFactory(content: content, mapGenerator: FlatMapGenerator())
        w = factory.newWorld(seed: seed)
        home = w.map.spawn.point
        var rng = SeededRandom(state: seed &* 0x9E37_79B9_7F4A_7C15 &+ 1)
        let area = w.base.area!
        let outcropDistance = rng.int(in: 8...20)
        ironOutcrop = GridPoint(area.origin.x - outcropDistance, home.y + rng.int(in: -6...6))
        ironVein = GridPoint(ironOutcrop.x - rng.int(in: 6...12), ironOutcrop.y)
        coalVein = GridPoint(home.x + rng.int(in: 12...20), home.y + rng.int(in: -4...4))
        let iron = DepositGenerator.make(id: "deposit.outcrop", at: ironOutcrop, category: .iron, rng: &rng,
                                         primaryPercent: 20...35)
        ironOutcropExtractions = iron.remainingExtractions
        let secondIron = DepositGenerator.make(id: "deposit.iron.second", at: ironVein, category: .iron, rng: &rng)
        let coal = DepositGenerator.make(id: "deposit.coal", at: coalVein, category: .coal, rng: &rng)
        w.map[.surface]?.deposits.add(iron)
        w.map[.surface]?.deposits.add(secondIron)
        w.map[.surface]?.deposits.add(coal)
    }

    var day: Int { w.clock.day }
    var isDay: Bool { w.clock.phase == .day && w.run.isActive }
    var crew: [PersonID] { w.people.members.filter { $0 != .noah }.sorted() }

    mutating func tick(_ seconds: Int = 1) {
        for _ in 0..<seconds where isDay {
            let before = furnaceFuelCount()
            let hot = hotFurnaces()
            _ = sim.advance(&w, realSeconds: 1.0)
            let after = furnaceFuelCount()
            if hot > 0 { result.furnaceHotSeconds[day, default: 0] += Int(SimStep.gameSeconds) }
            if after.charcoal < before.charcoal { result.charcoalUsed[day, default: 0] += before.charcoal - after.charcoal }
        }
    }

    mutating func walk(to point: GridPoint) {
        guard let from = w.people[.noah]?.position?.point, from != point else { return }
        let seconds = (from.chebyshev(to: point) + 3) / 4
        tick(seconds)
        w.people[.noah]?.position = WorldPoint(.surface, point)
    }

    func pocket(_ match: (Matter) -> Bool) -> (Int, Stuff?) {
        var total = 0
        var first: Stuff?
        for entry in w.inventory.entries(.person(.noah)) {
            if case .matter(let matter) = entry.stuff, match(matter) {
                total += entry.quantity
                first = first ?? entry.stuff
            }
        }
        return (total, first)
    }

    static func isOre(_ matter: Matter) -> Bool { matter.stage == .ore }
    static func isLump(_ matter: Matter) -> Bool { matter.stage == .metal && matter.shape == .lump }
    static func isPlate(_ matter: Matter) -> Bool { matter.stage == .metal && matter.shape == .plate }

    mutating func hold(_ id: HandworkID, _ stuff: Stuff?, until done: (WorldState) -> Bool = { _ in false }) {
        let selector = stuff.map { StockSelector(holder: .person(.noah), stuff: $0) }
        guard sim.apply(.production(.handwork(id: id, input: selector, holding: true)), to: &w).rejection == nil else { return }
        while isDay && w.placements.handwork[.noah]?.holding == true && !done(w) { tick() }
        _ = sim.apply(.production(.handwork(id: id, input: selector, holding: false)), to: &w)
    }

    mutating func mine(at deposit: GridPoint, until target: Int) {
        guard pocket(Self.isOre).0 < target else { return }
        walk(to: GridPoint(deposit.x + 1, deposit.y))
        hold(LineBotKit.mine, nil) { world in
            world.inventory.entries(.person(.noah)).reduce(0) { total, entry in
                if case .matter(let matter) = entry.stuff, Self.isOre(matter) { return total + entry.quantity }
                return total
            } >= target
        }
        walk(to: home)
    }

    mutating func craft(maxPlates: Int = .max) {
        var waited = 0
        while isDay, !furnaceIDs.isEmpty, hotFurnaces() == 0, waited < 40 { tick(); waited += 1 }
        let (_, ore) = pocket(Self.isOre)
        if let ore { hold(LineBotKit.smelt, ore) }
        var made = 0
        while isDay && made < maxPlates {
            let (_, lump) = pocket(Self.isLump)
            guard let lump else { return }
            let before = pocket(Self.isPlate).0
            hold(LineBotKit.hammer, lump) { world in
                world.inventory.entries(.person(.noah)).reduce(0) { total, entry in
                    if case .matter(let matter) = entry.stuff, Self.isPlate(matter) { return total + entry.quantity }
                    return total
                } > before
            }
            let after = pocket(Self.isPlate).0
            guard after > before else { return }
            made += after - before
        }
    }

    mutating func give(_ item: ItemID, _ quantity: Int, day: Int? = nil) {
        guard quantity > 0 else { return }
        var context = StepContext(world: w, content: sim.content)
        context.addStock(.item(item), quantity, to: .base)
        w = context.world
        if let day { result.provisioned[day, default: [:]][item, default: 0] += quantity }
    }

    mutating func provisionModule(_ kind: ModuleKindID) {
        guard let def = sim.content.modules[kind] else { return }
        provision(def.cost)
    }

    mutating func provisionStructure(_ kind: StructureKindID) {
        guard let def = sim.content.structures[kind] else { return }
        provision(def.cost)
    }

    mutating func provision(_ cost: [Ingredient]) {
        for ingredient in cost {
            if let item = ingredient.item { give(item, ingredient.quantity, day: day) }
        }
    }

    mutating func putFuel(_ item: ItemID, _ quantity: Int, into furnace: EntityID) {
        var context = StepContext(world: w, content: sim.content)
        guard let origins = context.takeStock(quantity, from: .base, where: { $0.stuff == .item(item) && $0.unique == nil }) else { return }
        ModuleRuntime.put(StockEntry(stuff: .item(item), quantity: quantity, origins: origins),
                          into: &context.world.placements.items[furnace]!.module!.input)
        w = context.world
    }

    mutating func emulateCoalHaul() {
        guard coalBudget > 0, let mine = coalMine, let furnace = furnaceIDs.first, let route = coalRoute,
              w.people.members.contains(where: { w.people[$0]?.assignment == .haul(route: route) }),
              let out = w.placements.items[mine]?.module?.output.first(where: { $0.stuff == .item(LineBotKit.coal) }) else { return }
        let n = min(coalBudget, out.quantity, 2)
        guard n > 0 else { return }
        var context = StepContext(world: w, content: sim.content)
        let taken = ModuleRuntime.take(n, from: &context.world.placements.items[mine]!.module!.output,
                                       where: { $0.stuff == .item(LineBotKit.coal) })
        for entry in taken { ModuleRuntime.put(entry, into: &context.world.placements.items[furnace]!.module!.input) }
        w = context.world
        coalBudget -= taken.reduce(0) { $0 + $1.quantity }
    }

    /// Noah's morning errand in path B: bring preheat charcoal from the kiln stock into the furnace.
    mutating func fetchKilnCharcoal(_ quantity: Int) {
        guard let furnace = furnaceIDs.first else { return }
        for kiln in kilnIDs {
            var context = StepContext(world: w, content: sim.content)
            guard let origins = context.takeStock(quantity, from: .placement(kiln), where: { $0.stuff == .item(LineBotKit.charcoal) && $0.unique == nil }) else { continue }
            ModuleRuntime.put(StockEntry(stuff: .item(LineBotKit.charcoal), quantity: quantity, origins: origins),
                              into: &context.world.placements.items[furnace]!.module!.input)
            w = context.world
            return
        }
    }

    mutating func heat(_ furnace: EntityID, fuel: ItemID, reserve: Int) {
        if reserve > 0 { putFuel(fuel, reserve, into: furnace) }
        let response = sim.apply(.base(.hearth(placement: furnace, op: .preheat)), to: &w)
        if response.rejection == nil { result.charcoalUsed[day, default: 0] += fuel == LineBotKit.charcoal ? 2 : 0 }
    }

    mutating func place(_ kind: ModuleKindID, at point: GridPoint, designStep: Int? = nil) -> EntityID? {
        let command: Command
        if let design, let designStep {
            command = .production(.placeFromDesign(design: design, stepIndex: designStep,
                                                     at: WorldPoint(.surface, point), facing: .east))
        } else {
            command = .production(.place(module: kind, at: WorldPoint(.surface, point), facing: .east))
        }
        guard sim.apply(command, to: &w).rejection == nil else { return nil }
        return w.placements.at(WorldPoint(.surface, point)).first
    }

    mutating func buildKiln(at point: GridPoint) -> EntityID? {
        provisionStructure(LineBotKit.kiln)
        // Research/unlock is outside W-05 (W-13 replaces this); grant the structure, like the materials.
        w.research.unlocked.structures.insert(LineBotKit.kiln)
        guard sim.apply(.base(.build(structure: LineBotKit.kiln, at: WorldPoint(.surface, point), facing: .east)), to: &w).rejection == nil,
              let id = w.placements.at(WorldPoint(.surface, point)).first else { return nil }
        for person in crew { w.people[person]?.assignment = .build(placement: id) }
        tick(68)
        for person in crew { w.people[person]?.assignment = .idle }
        kilnIDs.append(id)
        return id
    }

    mutating func assignKilns(_ count: Int) {
        for person in crew { w.people[person]?.assignment = .idle }
        for (person, kiln) in zip(crew, kilnIDs.prefix(count)) {
            w.people[person]?.assignment = .gather(interaction: LineBotKit.burnCharcoal,
                                                     at: w.placements.items[kiln]!.at)
        }
    }

    /// Kiln workers first, then haulers per route; everyone else rests so the idle
    /// pool does not haul for free (the Labor ledger already counts their hours as felling).
    mutating func assignHaulers(_ plan: [(route: EntityID?, count: Int)]) {
        var free = Array(crew.dropFirst(kilnIDs.count))
        for (route, count) in plan {
            guard let route else { continue }
            for _ in 0..<count where !free.isEmpty { w.people[free.removeFirst()]?.assignment = .haul(route: route) }
        }
        for person in free { w.people[person]?.assignment = .rest }
    }

    mutating func labor(assignedHours: Int) {
        let bounded = min(32, max(0, assignedHours))
        let shortfall = max(0, assignedHours - 32)
        let felling = 32 - bounded
        let chop = sim.content.interactions[LineBotKit.chopWood]
        let perHour = (chop?.yields.first?.min ?? 0) * 3600 / max(1, chop?.seconds ?? 1)
        let wood = felling * perHour * (sim.content.crewWork?.gatherPermille ?? 600) / 1000
        result.labor[day] = .init(assignedHours: bounded, fellingHours: felling, woodAdded: wood)
        if shortfall > 0 { result.laborShortfall[day] = shortfall }
        give(LineBotKit.wood, wood)
    }

    mutating func sleepAndRecord() {
        var seconds = 0
        while w.clock.phase == .day && w.run.isActive {
            tick(); seconds += 1
            if seconds % 10 == 0 { emulateCoalHaul() }
            if autoHeat, seconds % 20 == 0, let furnace = furnaceIDs.first,
               let item = w.placements.items[furnace], !FurnaceHeat.isHot(item, sim.content) {
                // Path B: preheat needs 2 charcoal from the kiln, and only pays off once coal is in the inlet.
                if heatFuel == LineBotKit.coal, furnaceFuelCount().coal > 0, furnaceFuelCount().charcoal == 0 {
                    fetchKilnCharcoal(2)
                }
                heat(furnace, fuel: heatFuel, reserve: 0)
            }
        }
        let completedDay = day
        _ = sim.apply(.time(.sleep), to: &w)
        record(day: completedDay)
    }

    mutating func record(day: Int) {
        for record in w.ledger.records where record.day == day {
            switch (record.act, record.subject) {
            case (.crafted, _):
                if record.detail["module"] == .string(LineBotKit.anvil.rawValue) { result.plates[day, default: 0] += record.count }
            case (.produced, .module(let module, _)) where module == LineBotKit.anvil:
                result.plates[day, default: 0] += record.count
            case (.mined, _): result.handOre[day, default: 0] += record.count
            case (.produced, .module(let module, _)) where module == LineBotKit.minehead:
                result.lineOre[day, default: 0] += record.count
            default: break
            }
        }
        let onHand = [HolderID.base, .person(.noah)].reduce(0) { total, holder in
            total + w.inventory.entries(holder).reduce(0) { sum, entry in
                if case .matter(let matter) = entry.stuff, Self.isPlate(matter) { return sum + entry.quantity }
                return sum
            }
        }
        result.platesOnHandAtDawn[w.clock.day] = onHand
    }

    func furnaceFuelCount() -> (charcoal: Int, coal: Int) {
        furnaceIDs.reduce(into: (charcoal: 0, coal: 0)) { count, id in
            guard let input = w.placements.items[id]?.module?.input else { return }
            for entry in input where entry.unique == nil {
                if entry.stuff == .item(LineBotKit.charcoal) { count.charcoal += entry.quantity }
                if entry.stuff == .item(LineBotKit.coal) { count.coal += entry.quantity }
            }
        }
    }

    func hotFurnaces() -> Int {
        furnaceIDs.reduce(0) { $0 + (w.placements.items[$1].map { FurnaceHeat.isHot($0, sim.content) } == true ? 1 : 0) }
    }

    static func handOnly(content: ContentDB, seed: UInt64, days: Int) -> LineBotResult {
        var bot = LineBot(content: content, seed: seed)
        while bot.day <= days && bot.w.run.isActive {
            if bot.day == 2 {
                bot.provisionModule(LineBotKit.furnace)
                if let furnace = bot.place(LineBotKit.furnace, at: bot.home) { bot.furnaceIDs = [furnace] }
            }
            if let furnace = bot.furnaceIDs.first {
                // W-05 grants only the hand-maintenance charcoal (at most ten), never wood.
                bot.give(LineBotKit.charcoal, 6)
                bot.heat(furnace, fuel: LineBotKit.charcoal, reserve: 4)
                bot.mine(at: bot.ironOutcrop, until: 6)
                bot.craft()
            }
            bot.sleepAndRecord()
        }
        return bot.result
    }

    static func line(content: ContentDB, seed: UInt64, path: LineBotPath, days: Int) -> LineBotResult {
        var bot = LineBot(content: content, seed: seed)
        var ironRoute: EntityID?
        var coalRoute: EntityID?
        while bot.day <= days && bot.w.run.isActive {
            if bot.day == 2 {
                bot.provisionModule(LineBotKit.furnace)
                _ = bot.sim.apply(.invention(.makeDesign(steps: [.minehead, .charcoalFurnace, .anvil])), to: &bot.w)
                bot.design = bot.w.invention.designs.keys.max()
                if let furnace = bot.place(LineBotKit.furnace, at: bot.home, designStep: 1) { bot.furnaceIDs = [furnace] }
            }
            if bot.day == 3, let design = bot.design {
                bot.provisionModule(LineBotKit.minehead)
                bot.provisionModule(LineBotKit.anvil)
                _ = bot.place(LineBotKit.minehead, at: bot.ironOutcrop, designStep: 0)
                if let anvil = bot.place(LineBotKit.anvil, at: GridPoint(bot.home.x + 1, bot.home.y), designStep: 2) { bot.anvilIDs.append(anvil) }
                _ = bot.buildKiln(at: GridPoint(bot.home.x - 2, bot.home.y))
                _ = design
            }
            if bot.day == 4 {
                bot.provisionModule(LineBotKit.anvil)
                if let anvil = bot.place(LineBotKit.anvil, at: GridPoint(bot.home.x + 2, bot.home.y)) { bot.anvilIDs.append(anvil) }
            }
            if bot.day == 5 {
                switch path {
                case .A:
                    _ = bot.buildKiln(at: GridPoint(bot.home.x - 3, bot.home.y))
                case .B:
                    bot.provisionModule(LineBotKit.minehead)
                    _ = bot.place(LineBotKit.minehead, at: bot.coalVein)
                }
            }
            if (6...8).contains(bot.day), let outcrop = bot.w.map[.surface]?.deposits.deposit(at: bot.ironOutcrop),
               outcrop.remainingExtractions * 3 < bot.ironOutcropExtractions, bot.furnaceIDs.count == 1 {
                bot.provisionModule(LineBotKit.minehead)
                bot.provisionModule(LineBotKit.furnace)
                bot.provisionModule(LineBotKit.anvil)
                if let mine = bot.place(LineBotKit.minehead, at: bot.ironVein),
                   let furnace = bot.place(LineBotKit.furnace, at: GridPoint(bot.ironVein.x + 1, bot.ironVein.y)),
                   let anvil = bot.place(LineBotKit.anvil, at: GridPoint(bot.ironVein.x + 2, bot.ironVein.y)) {
                    bot.furnaceIDs.append(furnace)
                    bot.anvilIDs.append(anvil)
                    _ = bot.sim.apply(.logistics(.link(from: .placement(mine), to: .placement(furnace))), to: &bot.w)
                    _ = bot.sim.apply(.logistics(.link(from: .placement(furnace), to: .placement(anvil))), to: &bot.w)
                }
            }

            let mine = bot.w.placements.at(WorldPoint(.surface, bot.ironOutcrop)).first
            if let mine, let furnace = bot.furnaceIDs.first {
                _ = bot.sim.apply(.logistics(.link(from: .placement(mine), to: .placement(furnace))), to: &bot.w)
                ironRoute = bot.w.logistics.routes.values.first { $0.from == .placement(mine) && $0.to == .placement(furnace) }?.id
            }
            if path == .B, let mine = bot.w.placements.at(WorldPoint(.surface, bot.coalVein)).first,
               let furnace = bot.furnaceIDs.first {
                _ = bot.sim.apply(.logistics(.link(from: .placement(mine), to: .placement(furnace))), to: &bot.w)
                coalRoute = bot.w.logistics.routes.values.first { $0.from == .placement(mine) && $0.to == .placement(furnace) }?.id
                bot.coalMine = mine
                bot.coalRoute = coalRoute
                if let r = coalRoute, let distance = bot.w.logistics.routes[r]?.distance {
                    bot.coalDailyCapacity = (HaulRules.perDay(crewMilli: 1000, distance: distance, bot.sim.content.hauling))
                }
            }
            for kiln in bot.kilnIDs {
                if let furnace = bot.furnaceIDs.first {
                    _ = bot.sim.apply(.logistics(.link(from: .placement(kiln), to: .placement(furnace))), to: &bot.w)
                }
            }

            for anvil in bot.anvilIDs {
                if let furnace = bot.furnaceIDs.first {
                    _ = bot.sim.apply(.logistics(.link(from: .placement(furnace), to: .placement(anvil))), to: &bot.w)
                }
            }
            func route(_ from: EntityID?, _ to: EntityID?) -> EntityID? {
                guard let from, let to else { return nil }
                return bot.w.logistics.routes.values.first { $0.from == .placement(from) && $0.to == .placement(to) }?.id
            }
            // Four crew only.  Ore haul = 1; fuel haul per brief (A: 1, then 2 from day 9; B: coal 1); kiln workers
            // are cut first when the four are exceeded (hand-favourable), recorded in laborShortfall.
            var kilnWorkers = path == .A && bot.day >= 5 ? 2 : (bot.kilnIDs.isEmpty ? 0 : 1)
            let fuelHaulers = path == .A ? (bot.day >= 9 ? 2 : 1) : 1
            let overflow = max(0, kilnWorkers + fuelHaulers + 1 - 4)
            kilnWorkers = max(bot.kilnIDs.isEmpty ? 0 : 1, kilnWorkers - overflow)
            let construction = bot.day == 3 || bot.day == 5 ? 6 : 0
            let kilnFuelRoute = route(bot.kilnIDs.first, bot.furnaceIDs.first)
            let fuelRoute = path == .B && bot.day >= 5 ? coalRoute : kilnFuelRoute
            bot.labor(assignedHours: (kilnWorkers + fuelHaulers + 1) * 8 + construction)
            if overflow > 0 { bot.result.laborShortfall[bot.day, default: 0] += overflow * 8 }
            bot.assignKilns(kilnWorkers)
            bot.assignHaulers([(ironRoute, 1), (fuelRoute, fuelHaulers)])
            bot.autoHeat = true
            bot.coalBudget = path == .B && bot.day >= 5 ? bot.coalDailyCapacity : 0
            bot.heatFuel = path == .B && bot.day >= 5 ? LineBotKit.coal : LineBotKit.charcoal
            if let furnace = bot.furnaceIDs.first {
                let fuel = path == .B && bot.day >= 5 ? LineBotKit.coal : LineBotKit.charcoal
                if bot.day <= 4 {
                    // Bootstrap grant until the first kiln output reaches the furnace (recorded in provisioned).
                    bot.give(LineBotKit.charcoal, 6, day: bot.day)
                    bot.heat(furnace, fuel: LineBotKit.charcoal, reserve: 4)
                } else {
                    bot.heat(furnace, fuel: fuel, reserve: 0)
                }
            }
            if bot.day <= 2 {
                bot.mine(at: bot.ironOutcrop, until: 6)
                bot.craft()
            }
            bot.sleepAndRecord()
        }
        return bot.result
    }
}
