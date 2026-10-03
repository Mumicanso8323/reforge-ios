import RFContent
import RFKernel
import RFMap
import RFRules
import RFWorld

/// 拠点(CORE-14)。建造物を置き、建てる(仲間が手伝うと速い)、片付ける、生存者を迎える(収容 = シェルターの数)。
///
/// 書いてよい切れ端: placements(建造物) / base。乱数の流れ: .base(いまは使わない)。受けるコマンド: .base(...)。
///
/// - 建てる: 費用を拠点の蓄えから取り、建造中(進み 0...1000)で置く。そばで止まっている一員が建てる
///   (ノアは手が空いていれば、仲間は配属 build のとき)。1 人 = 1 倍、専門が合えば +30%、範囲の効果の workSpeed を掛ける。
///   置いた・建てたはどちらも来歴に残る(置いたの来歴が Placement.origin、建てたの inputs に置いたの来歴)。
/// - 片付ける: 費用は全部戻る(戻せる操作なので確認を出さない)。
/// - 迎える: 会った人を、食料(BaseDef.welcomeRequires)と空いた寝床(収容の合計 > 一員の数)があれば一員にする。
///   実際に一員にするのは RFCrew(joinFromEffect)。来歴は rescued。
public struct BaseSystem: SimSystem {
    public let name = "base"
    public init() {}

    public func handle(_ command: Command, _ ctx: inout StepContext) -> CommandResult {
        guard case .base(let c) = command else { return .notMine }
        switch c {
        case .build(let kind, let at, let facing):
            return Construction.build(kind, at: at, facing: facing, &ctx)
        case .selfBuild(let person, let structure, let near, let radius, let cause):
            return Construction.selfBuild(person: person, structure: structure, near: near, radius: radius, cause: cause, &ctx)
        case .demolish(let e):
            return Construction.demolish(e, &ctx)
        case .welcome(let person):
            return Welcome.welcome(person, &ctx)
        case .destroyFromEffect(let near, let radius, let structure, let max, let cause):
            for id in Destruction.targets(near: near, radius: radius, max: max, in: ctx.world, where: { p in
                guard case .structure(let k) = p.kind else { return false }
                return structure.map { $0 == k } ?? true
            }) { Destruction.destroy(id, cause: cause, &ctx) }
            return .done
        case .repair(let placement):
            return Construction.repair(placement, &ctx)
        case .hearth(let placement, let op):
            return HearthCommands.handle(placement, op, &ctx)
        }
    }

    public func step(_ ctx: inout StepContext) {
        Construction.advance(&ctx)
        Hearths.advanceStructures(seconds: Int(SimStep.gameSeconds), &ctx)
    }

    public func react(to event: DomainEvent, _ ctx: inout StepContext) {
        switch event {
        case .phaseChanged(.dusk, _): Hearths.markDusk(&ctx)
        case .dawn: Hearths.countDawn(&ctx)
        default: break
        }
    }
}

/// 拠点の数(保存しない。placements と content から計算する)。画面と他のシステムも同じ式を使えるよう公開。
public enum BaseRules {
    /// 建ち終えた建造物の provides[tag] の合計。
    public static func total(_ tag: String, _ w: WorldState, _ content: ContentDB) -> Int {
        w.placements.items.values.reduce(0) { acc, p in
            guard case .structure = p.kind, p.status == .running else { return acc }
            return acc + (Hearths.provides(p, content)[tag] ?? 0)
        }
    }

    /// 迎えられる人数の上限(収容の合計)。
    public static func housing(_ w: WorldState, _ content: ContentDB) -> Int {
        total(content.base.housingTag ?? "housing", w, content)
    }

    /// 保管のスロットの合計(拠点の蓄えの上限。上限の守り方は在庫の共通操作の担当)。
    public static func storageSlots(_ w: WorldState, _ content: ContentDB) -> Int { total("storage", w, content) }

    /// 拠点の範囲の中心。
    public static func center(_ w: WorldState) -> GridPoint? {
        w.base.area.map { GridPoint($0.origin.x + $0.size.width / 2, $0.origin.y + $0.size.height / 2) }
    }
}
