import RFKernel

extension RuleBook {
    /// R1 の規則の表(order.md §5.4 の発明の表。差分と理由は README.md)。
    ///
    /// - 採掘口: 並びの先頭でだけ動き、鉱脈の純度のまま鉱石(塊)を出す。
    /// - 石臼: 鉱石の塊を粉にする(レシピ `crush`)。
    /// - 洗い樋: 粉なら砂が流れて純度が上がる(レシピ `wash`)。塊のままでは変わらない。混ぜてあった石灰は流れる。
    /// - 混ぜ鉢(石灰石): 炉の前に混ぜると、炉で不純物がスラグになって抜ける。炉の後では効かない。石灰石以外は馴染まない。
    /// - 炉: 木炭なら鉱石が溶けて鉄の塊になる(レシピ `charcoal_smelt`)。薪では温度が足りず溶けない。
    ///   鉄を熱し直すと、急冷の硬さが抜けて、また叩ける。
    /// - 叩き台: 熱い鉄を板にする。熱し直した板をもう一度叩くと純度が上がる(叩き重ね、2 回まで)。
    ///   冷めかけた鉄は伸びない。急冷の後に叩くと割れる。
    /// - 水槽: 叩いた後の鉄を急冷すると剛。叩いていない塊は冷やしても硬くならない。
    /// - 並びの最後: 熱いまま残った板は空気で冷えて柔になる。
    public static let r1 = RuleBook(
        modules: [
            .minehead: [
                ModuleRule(when: .init(position: .first), then: []),
                ModuleRule(when: .any, then: [.finding(.mineheadNotAtHead, [.module])]),
            ],
            .millstone: [
                ModuleRule(
                    when: .init(stage: .ore, shapes: [.lump]),
                    then: [.applyRecipe(.crush), .setShape(.dust), .byproduct(.crushedStone)]),
                ModuleRule(when: .init(stage: .ore, shapes: [.dust]), then: [.finding(.crushAlreadyDust, [])]),
                ModuleRule(when: .init(stage: .metal), then: [.finding(.crushMetalTooTough, [.shape])]),
            ],
            .sluice: [
                ModuleRule(
                    when: .init(stage: .ore, shapes: [.dust], carries: .limestone),
                    then: [
                        .consume(.water, 1), .applyRecipe(.wash), .dropAdditives, .byproduct(.sand),
                        .finding(.washFluxWashedAway, []),
                    ]),
                ModuleRule(
                    when: .init(stage: .ore, shapes: [.dust]),
                    then: [.consume(.water, 1), .applyRecipe(.wash), .byproduct(.sand)]),
                ModuleRule(
                    when: .init(stage: .ore),
                    then: [.consume(.water, 1), .finding(.washLumpNoEffect, [.shape])]),
                ModuleRule(
                    when: .init(stage: .metal),
                    then: [.consume(.water, 1), .finding(.washMetalNoEffect, [.shape])]),
            ],
            .mixingBowl: [
                ModuleRule(when: .init(input: .absent), then: [.finding(.mixNothingAdded, [])]),
                ModuleRule(
                    when: .init(stage: .metal),
                    then: [.consumeStepInputs, .finding(.mixAfterSmeltNoEffect, [.stepInput])]),
                ModuleRule(
                    when: .init(stage: .ore, carries: .limestone, input: .exactly([.limestone])),
                    then: [.consumeStepInputs, .finding(.mixAlreadyMixed, [.stepInput])]),
                ModuleRule(
                    when: .init(stage: .ore, input: .exactly([.limestone])),
                    then: [.consumeStepInputs, .carry(.limestone)]),
                ModuleRule(
                    when: .init(stage: .ore),
                    then: [.consumeStepInputs, .finding(.mixUnknownAdditive, [.stepInput])]),
            ],
            .furnace: [
                ModuleRule(when: .init(input: .absent), then: [.finding(.furnaceNoFuel, [])]),
                ModuleRule(
                    when: .init(input: .exactly([.wood])),
                    then: [.consumeStepInputs, .finding(.furnaceTooCool, [.stepInput])]),
            ] + smelt(fuel: .charcoal, recipe: .charcoalSmelt) + smelt(fuel: .coal, recipe: .basicSmelt),
            .anvil: [
                ModuleRule(when: .init(stage: .ore), then: [.finding(.hammerOreNoEffect, [.shape])]),
                ModuleRule(
                    when: .init(stage: .metal, tempers: [.cracked]),
                    then: [.finding(.hammerAlreadyCracked, [])]),
                ModuleRule(
                    when: .init(stage: .metal, thermal: [.quenched]),
                    then: [.setTemper(.cracked), .finding(.hammerCrackedAfterQuench, [.shape])]),
                ModuleRule(
                    when: .init(stage: .metal, thermal: [.warm, .airCooled, .ambient]),
                    then: [.finding(.hammerTooCool, [.shape])]),
                ModuleRule(
                    when: .init(stage: .metal, thermal: [.hot], workedMax: 0),
                    then: [.setShape(.plate), .addWorked(1), .setThermal(.warm), .setTemper(.none)]),
                ModuleRule(
                    when: .init(stage: .metal, thermal: [.hot], workedMin: 1, workedMax: 2),
                    then: [.applyRecipe(.fold), .addWorked(1), .setThermal(.warm), .setTemper(.none)]),
                ModuleRule(
                    when: .init(stage: .metal, thermal: [.hot]),
                    then: [.finding(.hammerNoFurther, [])]),
            ],
            .quenchTank: [
                ModuleRule(when: .init(stage: .ore), then: [.finding(.quenchOreNoEffect, [.shape])]),
                ModuleRule(
                    when: .init(stage: .metal, thermal: [.hot, .warm], tempers: [.cracked]),
                    then: [.setThermal(.quenched)]),
                ModuleRule(
                    when: .init(stage: .metal, thermal: [.hot, .warm], workedMin: 1),
                    then: [.setThermal(.quenched), .setTemper(.hard)]),
                ModuleRule(
                    when: .init(stage: .metal, thermal: [.hot, .warm]),
                    then: [.setThermal(.quenched), .finding(.quenchUnworkedNotHardened, [.shape])]),
                ModuleRule(when: .init(stage: .metal), then: [.finding(.quenchAlreadyCold, [])]),
            ],
        ],
        finish: [
            ModuleRule(when: .init(stage: .ore), then: [.finding(.endedAsOre, [])]),
            ModuleRule(
                when: .init(stage: .metal, thermal: [.hot, .warm], workedMin: 1, tempers: [.none]),
                then: [.setThermal(.airCooled), .setTemper(.soft)]),
            ModuleRule(when: .init(stage: .metal, thermal: [.hot, .warm]), then: [.setThermal(.airCooled)]),
        ],
        metrics: [
            MetricRule(when: .init(stage: .ore), hardness: 65, toughness: 10),
            MetricRule(when: .init(stage: .metal, tempers: [.cracked]), hardness: 85, toughness: 0),
            MetricRule(when: .init(stage: .metal, tempers: [.hard]), hardness: 85, toughness: 30),
            MetricRule(when: .init(stage: .metal, tempers: [.soft]), hardness: 40, toughness: 80),
            MetricRule(when: .init(stage: .metal, workedMin: 1), hardness: 60, toughness: 55),
            MetricRule(when: .init(stage: .metal), hardness: 60, toughness: 45),
        ],
        recipes: .r1)

    /// 燃料ごとの炉の規則(鉱石を溶かす・鉄を熱し直す)。
    static func smelt(fuel: ItemID, recipe: RecipeID) -> [ModuleRule] {
        let melt: [RuleEffect] = [
            .consumeStepInputs, .applyRecipe(recipe), .becomes(.metal, .iron), .setShape(.lump),
            .setThermal(.hot), .setTemper(.none), .byproduct(.exhaust),
        ]
        return [
            ModuleRule(
                when: .init(stage: .ore, carries: .limestone, input: .exactly([fuel])),
                then: melt + [.dropAdditives, .byproduct(.slag)]),
            ModuleRule(when: .init(stage: .ore, input: .exactly([fuel])), then: melt),
            // 割れた鉄は熱し直しても割れたまま
            ModuleRule(
                when: .init(stage: .metal, tempers: [.cracked], input: .exactly([fuel])),
                then: [.consumeStepInputs, .setThermal(.hot), .byproduct(.exhaust)]),
            // 熱し直すと急冷の硬さは抜ける(焼きなまし)。叩いた回数は残る
            ModuleRule(
                when: .init(stage: .metal, input: .exactly([fuel])),
                then: [.consumeStepInputs, .setThermal(.hot), .setTemper(.none), .byproduct(.exhaust)]),
        ]
    }
}
