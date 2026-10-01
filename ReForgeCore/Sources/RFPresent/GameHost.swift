import RFContent
import RFKernel
import RFSim
import RFWorld

/// 世界状態を 1 つ持ち、画面からの意図を順に本体へ渡す係(C-engine-ui.md §5)。
///
/// - actor なので、シミュレーションは主スレッドの外で動く(マップの 60fps の描画を邪魔しない)。
/// - 画面は send / tick を呼び、返ってくる Frame を主スレッドの @Observable に写すだけ。
/// - 一時停止・アプリの非アクティブは画面側の判断で tick を呼ばないことで表す(本体は壁時計を読まない)。
/// - 走行の再現のため、受けたコマンドを (ステップ番号, コマンド) で記録できる(replayLog)。
public actor GameHost {
    public let simulation: Simulation
    public let builder: FrameBuilder
    public private(set) var world: WorldState
    public private(set) var frame: Frame
    public private(set) var replayLog: [(step: Int64, command: Command)] = []
    private var revision = 0

    public init(simulation: Simulation, world: WorldState) {
        self.simulation = simulation
        self.builder = FrameBuilder(content: simulation.content)
        self.world = world
        self.frame = builder.build(world, revision: 0, previous: nil, report: nil)
    }

    /// 意図を送る。断られたら理由を返す(画面は足元カードに 1 行出す。ダイアログは出さない)。
    @discardableResult
    public func send(_ command: Command) -> (frame: Frame, report: StepReport) {
        replayLog.append((world.clock.now.seconds / SimStep.gameSeconds, command))
        let r = simulation.apply(command, to: &world)
        return (rebuild(r), r)
    }

    /// 昼の実時間を進める(画面のタイマーから。止めているときは呼ばない)。
    @discardableResult
    public func tick(realSeconds: Double) -> (frame: Frame, report: StepReport) {
        let r = simulation.advance(&world, realSeconds: realSeconds)
        guard r.steps > 0 || !r.events.isEmpty else { return (frame, r) }
        return (rebuild(r), r)
    }

    /// 保存から戻す・巻き戻すなどで世界を差し替える。
    public func replace(world w: WorldState) -> Frame {
        world = w
        revision += 1
        frame = builder.build(w, revision: revision, previous: nil, report: nil)
        return frame
    }

    // MARK: - 画面からの引き出し(世界状態は渡さない)

    /// 区画の中身(画面が版の変わった区画だけ引く)。
    public func chunks(_ indices: [Int]) -> [MapChunk] { builder.chunks(world, indices, map: frame.map) }

    /// 長押しで調べる。
    public func inspect(at p: GridPoint) -> TileInspection? { builder.inspect(world, at: p) }

    /// 足元カード。
    public func footCard(at p: GridPoint) -> FootCard? { builder.footCard(world, at: p) }

    /// 工程表。
    public func sheet(_ s: ProcessSheet.Source) -> ProcessSheet? { builder.sheet(s, in: world) }

    private func rebuild(_ r: StepReport) -> Frame {
        revision += 1
        frame = builder.build(world, revision: revision, previous: frame, report: r)
        return frame
    }
}
