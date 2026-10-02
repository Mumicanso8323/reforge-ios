import RFAbilities
import RFBase
import RFCombat
import RFContent
import RFCrew
import RFExploration
import RFFailure
import RFInvention
import RFKernel
import RFLogistics
import RFMap
import RFNarrative
import RFProduction
import RFResearch
import RFRules
import RFSurvival
import RFTime
import RFWorld

/// ゲーム本体(C-engine-ui.md)。画面は意図(Command)を送り、本体は世界を進めて結果(StepReport)を返す。
///
/// - 値型で状態を持たない。世界状態は呼び出し側(GameHost)が 1 つ持ち、inout で渡す。
/// - 決定的: 同じ seed・同じ (ステップ番号, コマンド) の並びなら、同じ世界・同じ出来事の列になる。
/// - 時間は固定ステップ(SimStep.gameSeconds)。昼は実時間を割ってステップ数にし、夜作業は行為の時間、
///   寝るは夜明けまでのステップを、すべて同じ step 関数で進める。
public struct Simulation: Sendable {
    public let content: ContentDB
    public let systems: [any SimSystem]

    /// 1 ステップで出来事の反応を何周まで回すか(反応が反応を呼ぶ連鎖の上限)。
    public static let maxReactionRounds = 16

    public init(content: ContentDB, systems: [any SimSystem] = Simulation.standardSystems) {
        self.content = content
        self.systems = systems
    }

    /// 既定のシステムと、毎ステップ呼ぶ順番(B-data-model.md §1 の持ち主の表と同じ並び)。
    /// 時間 → 人の移動と配属 → 探索 → 生産 → 運搬 → 拠点 → 研究 → 力 → 戦闘 → 生存 → 出来事 → 失敗。
    public static var standardSystems: [any SimSystem] {
        [TimeSystem(), CrewSystem(), ExplorationSystem(), ProductionSystem(), LogisticsSystem(), BaseSystem(),
         ResearchSystem(), AbilitiesSystem(), CombatSystem(), SurvivalSystem(), InventionSystem(), NarrativeSystem(),
         FailureSystem()]
    }

    // MARK: - コマンド

    /// コマンドを 1 つ処理する。夜作業の行為なら、その時間ぶんのステップも進める。
    public func apply(_ command: Command, to world: inout WorldState) -> StepReport {
        var report = StepReport()
        guard world.run.isActive else {
            report.rejection = Rejection("reason.run.not_active")
            return report
        }
        if let scene = world.narrative.scene,
           content.scenes[scene.scene]?.style == .prologue,
           command != .narrative(.advanceScene),
           !isFireFromEffect(command)
        {
            report.rejection = Rejection("reason.scene.prologue")
            return report
        }
        if world.clock.held, !hasPrologueScene(world), content.start.clock?.firstAct != nil,
           !acceptsWhileFirstActHeld(command)
        {
            report.rejection = Rejection("reason.start.first_act")
            return report
        }
        var ctx = StepContext(world: world, content: content)
        let result = dispatch(command, &ctx)
        if ctx.world.clock.held, content.start.clock?.firstAct == nil, case .accepted = result, Self.releasesHold(command) {
            // 最初の行為で時計が動き出す(W-01)。戻らない
            ctx.world.clock.held = false
            ctx.changes.mark(.clock)
        }
        let eventStart = report.events.count
        settle(&ctx, &report)
        releaseHeldAfterFirstAct(&ctx, events: report.events[eventStart...], report: &report)
        world = ctx.world
        switch result {
        case .rejected(let r): report.rejection = r
        case .accepted(let t?) where t.seconds > 0:
            let steps = Int((t.seconds + SimStep.gameSeconds - 1) / SimStep.gameSeconds)
            report.merge(runSteps(steps, &world))
        default: break
        }
        if Disclosure.record(&world, content) { report.changes.mark(.narrative) }
        return report
    }

    /// 時計の保留を解くコマンドか(W-01)。歩く・止まる・場面の送りは解かない。
    public static func releasesHold(_ command: Command) -> Bool {
        switch command {
        // 場面を送る(序・目覚めの行を読む)・効果から出来事を起こすも、プレイヤーの行為ではない(v0.5 §2.8.3)
        case .crew(.walk), .crew(.stop), .narrative(.advanceScene), .narrative(.fireFromEffect),
             .exploration(.inspected): false
        default: true
        }
    }

    private func isFireFromEffect(_ command: Command) -> Bool {
        if case .narrative(.fireFromEffect) = command { return true }
        return false
    }

    private func hasPrologueScene(_ world: WorldState) -> Bool {
        guard let scene = world.narrative.scene else { return false }
        return content.scenes[scene.scene]?.style == .prologue
    }

    /// firstAct を持つ始まりは、暗い画面の行為と場面・効果の内部命令だけを受ける。
    private func acceptsWhileFirstActHeld(_ command: Command) -> Bool {
        switch command {
        case .exploration(.interact(let interaction, _, _, let person)):
            return interaction == content.start.clock?.firstAct && (person == nil || person == .noah)
        case .narrative(.advanceScene), .narrative(.fireFromEffect):
            return true
        default:
            return false
        }
    }

    /// 「寝る」を押したらどうなるかの見込み(W-11)。世界の写しに同じ規則で .time(.sleep) を当てた結果。
    /// 本物の世界と乱数の流れは進めない(値型の写しで回す)。乱数の種も写しのものを使うので、同じ世界に
    /// 寝るを当てた実際の結果と必ず一致する。夜でない(断られる)ときは nil。
    public func forecastSleep(_ world: WorldState) -> (world: WorldState, report: StepReport)? {
        var copy = world
        let r = apply(.time(.sleep), to: &copy)
        guard r.rejection == nil else { return nil }
        return (copy, r)
    }

    public func dispatch(_ command: Command, _ ctx: inout StepContext) -> CommandResult {
        for s in systems {
            let r = s.handle(command, &ctx)
            if r != .notMine { return r }
        }
        ctx.warnings.append("どのシステムも受けないコマンド: \(command)")
        return .rejected(Rejection("reason.command.unhandled"))
    }

    // MARK: - 時間

    /// 昼の実時間を進める(画面のタイマーから。アプリが非アクティブ・一時停止・止める決断の間は呼ばない)。
    /// 昼でなければ何もしない(日没で時計は止まる)。
    /// 1 回の advance で受け取る実時間の上限(秒)。裏から戻った直後の大きな dt で、閉じていた間の分まで
    /// 昼が進まないようにする(閉じている間は進まない)。
    public static let maxRealSecondsPerAdvance = 1.0

    public func advance(_ world: inout WorldState, realSeconds: Double) -> StepReport {
        guard world.run.isActive, world.clock.phase == .day, !world.clock.held, realSeconds > 0, realSeconds.isFinite,
              !world.narrative.pending.contains(where: \.blocking)
        else { return StepReport() }
        let dt = min(realSeconds, Self.maxRealSecondsPerAdvance)
        let micros = Int64((dt * 1_000_000).rounded())
        let unit = Int64(content.clock.dayRealSeconds) * 1_000_000 * SimStep.gameSeconds
        world.clock.realCarry += micros * content.clock.dayGameSeconds
        let steps = Int(world.clock.realCarry / unit)
        world.clock.realCarry %= unit
        return runSteps(steps, &world, stopAtPhaseChange: true)
    }

    /// 時計を保留した始まりで、ノアが最初の押し続ける行為をしている間だけ進める。
    /// 繰り越しは保存する時計ではなく、呼び出し側が持つ carry を使う。
    public func advanceHeld(_ world: inout WorldState, realSeconds: Double, carry: inout Int64) -> StepReport {
        guard world.run.isActive, world.clock.held, let firstAct = content.start.clock?.firstAct,
              let active = world.exploration.active[.noah], active.interaction == firstAct, active.holding,
              realSeconds > 0, realSeconds.isFinite
        else { return StepReport() }
        let dt = min(realSeconds, Self.maxRealSecondsPerAdvance)
        let micros = Int64((dt * 1_000_000).rounded())
        let unit = Int64(content.clock.dayRealSeconds) * 1_000_000 * SimStep.gameSeconds
        carry += micros * content.clock.dayGameSeconds
        let steps = Int(carry / unit)
        carry %= unit
        guard steps > 0 else { return StepReport() }

        var report = StepReport()
        var ctx = StepContext(world: world, content: content)
        for _ in 0..<steps {
            guard ctx.world.run.isActive, ctx.world.clock.held,
                  ctx.world.exploration.active[.noah]?.interaction == firstAct,
                  ctx.world.exploration.active[.noah]?.holding == true
            else { break }
            Interactions.advance(&ctx, actor: .noah, interaction: firstAct)
            let eventStart = report.events.count
            settle(&ctx, &report)
            releaseHeldAfterFirstAct(&ctx, events: report.events[eventStart...], report: &report)
            report.steps += 1
            if !ctx.world.clock.held { carry = 0; break }
        }
        world = ctx.world
        return report
    }

    /// ステップを n 回進める。
    public func runSteps(_ n: Int, _ world: inout WorldState, stopAtPhaseChange: Bool = false) -> StepReport {
        var report = StepReport()
        guard n > 0 else { return report }
        var ctx = StepContext(world: world, content: content)
        for _ in 0..<n {
            guard ctx.world.run.isActive else { break }
            let phase = ctx.world.clock.phase
            for s in systems { s.step(&ctx) }
            settle(&ctx, &report)
            report.steps += 1
            if stopAtPhaseChange, ctx.world.clock.phase != phase { break }
            if ctx.world.narrative.pending.contains(where: \.blocking) { break }
        }
        world = ctx.world
        if Disclosure.record(&world, content) { report.changes.mark(.narrative) }
        return report
    }

    /// 出来事を全システムに配り、出た追加のコマンドを処理する(連鎖は maxReactionRounds 周まで)。
    public func settle(_ ctx: inout StepContext, _ report: inout StepReport) {
        for _ in 0..<Self.maxReactionRounds {
            let events = ctx.drainEvents()
            let follow = ctx.followUps
            ctx.followUps.removeAll()
            if events.isEmpty, follow.isEmpty { break }
            report.events += events
            for e in events { for s in systems { s.react(to: e, &ctx) } }
            for c in follow {
                if case .rejected(let r) = dispatch(c, &ctx) { ctx.warnings.append("効果のコマンドが断られた: \(r.reason)") }
            }
        }
        report.changes.merge(ctx.changes)
        ctx.changes = ChangeSet()
        report.warnings += ctx.warnings
        ctx.warnings.removeAll()
    }

    /// firstAct を完了しただけでは始めない。完了の出来事と、燃えている建造物の火床が同じ手順でそろった時だけ解く。
    private func releaseHeldAfterFirstAct(_ ctx: inout StepContext, events: ArraySlice<DomainEvent>,
                                          report: inout StepReport) {
        guard ctx.world.clock.held, let firstAct = content.start.clock?.firstAct,
              events.contains(where: { event in
                  if case .interacted(_, let interaction, _, _) = event { return interaction == firstAct }
                  return false
              }),
              ctx.world.placements.items.values.contains(where: { $0.structure?.hearth?.lit == true })
        else { return }
        ctx.world.clock.held = false
        ctx.changes.mark(.clock)
        report.changes.mark(.clock)
    }
}

/// 1 回の進行の結果。画面はこれで「何が変わったか」を知り、射影を作り直す。
public struct StepReport: Sendable {
    public var events: [DomainEvent] = []
    public var rejection: Rejection?
    public var changes = ChangeSet()
    public var steps = 0
    /// 仕組みがまだ無い効果など(テストは 0 件を確かめる)。
    public var warnings: [String] = []

    public init() {}

    public mutating func merge(_ o: StepReport) {
        events += o.events
        rejection = rejection ?? o.rejection
        changes.merge(o.changes)
        steps += o.steps
        warnings += o.warnings
    }
}
