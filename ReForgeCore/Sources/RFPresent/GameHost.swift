import RFContent
import RFKernel
import RFPerception
import RFRules
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
    /// 保留中の最初の行為だけに使う実時間の端数。保存しない。
    private var heldCarry: Int64 = 0

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
        if !world.clock.held { heldCarry = 0 }
        return (rebuild(r), r)
    }

    /// 昼の実時間を進める(画面のタイマーから。止めているときは呼ばない)。
    @discardableResult
    public func tick(realSeconds: Double) -> (frame: Frame, report: StepReport) {
        let r: StepReport
        if world.clock.held {
            r = simulation.advanceHeld(&world, realSeconds: realSeconds, carry: &heldCarry)
        } else {
            heldCarry = 0
            r = simulation.advance(&world, realSeconds: realSeconds)
        }
        guard r.steps > 0 || !r.events.isEmpty else { return (frame, r) }
        return (rebuild(r), r)
    }

    /// 保存から戻す・巻き戻すなどで世界を差し替える。
    public func replace(world w: WorldState) -> Frame {
        world = w
        heldCarry = 0
        revision += 1
        frame = builder.build(w, revision: revision, previous: nil, report: nil)
        return frame
    }

    /// 意図を送り、断られたらその理由(認識の層を通した 1 行)も返す。画面は足元カードに出す。
    public func perform(_ command: Command) -> (frame: Frame, rejection: String?) {
        let (f, r) = send(command)
        return (f, r.rejection.map { describe($0) })
    }

    /// 断った理由の 1 行(英語の ID は出さない)。
    public func describe(_ r: Rejection) -> String {
        Perceiver(content: simulation.content, world: world).text(r.reason)
    }

    // MARK: - 画面からの引き出し(世界状態は渡さない)

    /// 区画の中身(画面が版の変わった区画だけ引く)。
    public func chunks(_ indices: [Int]) -> [MapChunk] { builder.chunks(world, indices, map: frame.map) }

    /// 長押しで調べる。
    /// 調べたマスの種類は世界に覚える(条件 inspected。U20)。開示が変われば frame も作り直す(画面は host.frame を読む)。
    public func inspect(at p: GridPoint) -> TileInspection? {
        guard let r = builder.inspect(world, at: p) else { return nil }
        if let kinds = builder.inspectedKinds(world, at: p) {
            let c = Command.exploration(.inspected(terrain: kinds.terrain, poi: kinds.poi))
            replayLog.append((world.clock.now.seconds / SimStep.gameSeconds, c))
            let report = simulation.apply(c, to: &world)
            if !report.changes.areas.isEmpty { _ = rebuild(report) }
        }
        return r
    }

    /// 足元カード。
    public func footCard(at p: GridPoint) -> FootCard? { builder.footCard(world, at: p) }

    /// 工程表。
    public func sheet(_ s: ProcessSheet.Source) -> ProcessSheet? { builder.sheet(s, in: world) }

    /// 工程表の行に置ける答えの候補(自分の来歴から。新しい順)。
    public func answerCandidates(_ sheet: SheetID, row: String) -> [AnswerCandidate] {
        builder.answerCandidates(sheet, row: row, in: world)
    }

    /// 設計画面の材料(積める段・試す物・段に入れる物・札)。
    public func designBench() -> DesignBench { builder.designBench(in: world) }

    /// ノート(試したこと・所見・図鑑・手がかり・記録・資料)。
    public func notebook() -> NotebookPage { builder.notebook(in: world) }

    /// 資料を開く(開く条件が成り立っていなければ nil)。
    public func document(_ id: DocumentID) -> DocumentPage? { builder.document(id, in: world) }
    /// 拠点(蓄え・建てた物・建てられる物・運搬の経路)。
    public func base() -> BaseView { builder.base(world) }

    /// 仲間と割り当ての選択肢。
    public func crew() -> CrewView { builder.crew(world) }

    /// 置くモードの照準。
    public func placementPreview(_ kind: StructureKindID, at p: GridPoint) -> PlacementPreview {
        builder.placementPreview(world, kind: kind, at: p)
    }

    /// 再開の 1 行の材料(前回の最後の行為と今の目標。実時刻は持たない)。
    public func resumeLine() -> ResumeLine { builder.resumeLine(world) }

    /// 研究。
    public func research() -> ResearchView { builder.research(world) }

    private func rebuild(_ r: StepReport) -> Frame {
        revision += 1
        frame = builder.build(world, revision: revision, previous: frame, report: r)
        return frame
    }
}
