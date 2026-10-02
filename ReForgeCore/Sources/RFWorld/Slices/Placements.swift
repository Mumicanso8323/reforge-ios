import RFKernel
import RFMap
import RFMatter

/// 地図に置いた物。持ち主: モジュールは RFProduction、建造物は RFBase。
/// 手作業の途中(押し続けている進み)もここに持つ(生産の途中の状態。保存から戻れば続きから)。
public struct PlacementsState: Codable, Equatable, Sendable {
    public var items: [EntityID: Placement] = [:]
    /// 押し続ける手作業の途中(人 → 進み)。持ち主: RFProduction。
    public var handwork: [PersonID: HandworkSession] = [:]
    /// モジュールの置き場所・向きが変わるたびに増える番号(運搬の経路を作り直す合図。RFLogistics が見る)。
    public var topologyVersion: Int = 0

    public init() {}

    /// 位置の昇順(決定的に回すため)。
    public var sortedIDs: [EntityID] { items.keys.sorted() }

    public func at(_ p: WorldPoint) -> [EntityID] {
        items.filter { $0.value.covers(p) }.map(\.key).sorted()
    }

    /// 置いたモジュールだけ(ID 順)。
    public var moduleIDs: [EntityID] { sortedIDs.filter { items[$0]?.module != nil } }

    private enum CodingKeys: String, CodingKey { case items, handwork, topologyVersion }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decode([EntityID: Placement].self, forKey: .items)
        handwork = try c.decodeIfPresent([PersonID: HandworkSession].self, forKey: .handwork) ?? [:]
        topologyVersion = try c.decodeIfPresent(Int.self, forKey: .topologyVersion) ?? 0
    }
}

public enum PlaceableKind: Codable, Hashable, Sendable {
    case module(ModuleKindID)
    case structure(StructureKindID)
}

public struct Placement: Codable, Equatable, Sendable {
    public var id: EntityID
    public var kind: PlaceableKind
    public var at: WorldPoint
    public var facing: Direction
    /// 占めるマス(at からの相対。1 マスなら [(0,0)])。
    public var footprint: [GridPoint]
    /// 置いた・建てたときの来歴。後の開示が「あなたが置いたこれ」を指す。
    public var origin: ProvenanceID
    public var status: PlacementStatus
    public var module: ModuleRuntime?
    public var structure: StructureRuntime?
    /// 壊されたときの来歴(U16。直したら nil に戻る。直した記録の inputs に入る)。
    public var destroyedBy: ProvenanceID?

    public init(id: EntityID, kind: PlaceableKind, at: WorldPoint, facing: Direction,
                footprint: [GridPoint] = [GridPoint(0, 0)], origin: ProvenanceID, status: PlacementStatus) {
        self.id = id
        self.kind = kind
        self.at = at
        self.facing = facing
        self.footprint = footprint
        self.origin = origin
        self.status = status
    }

    public func covers(_ p: WorldPoint) -> Bool {
        p.layer == at.layer && footprint.contains { GridPoint(at.point.x + $0.x, at.point.y + $0.y) == p.point }
    }

    /// モジュールの種類(建造物なら nil)。
    public var moduleKind: ModuleKindID? {
        if case .module(let k) = kind { k } else { nil }
    }
}

public enum PlacementStatus: Codable, Equatable, Sendable {
    /// 建造中(進み具合 0...1000)。
    case underConstruction(progress: Int)
    case running
    /// 止まっている(理由は文字列表のキー。「燃料が来ていない」など)。何が来ていないかは ModuleRuntime.waitingFor。
    case stopped(reason: TextID)
    /// 壊れた(R2 の保守)。
    case broken
}

/// 入出口(向きを当てた後の絶対の辺)。隣のモジュールの入口と自分の出口が向き合えば、運び手なしでつながる。
public struct ModulePorts: Codable, Equatable, Sendable {
    public var inputs: [Direction]
    public var outputs: [Direction]

    public init(inputs: [Direction] = [], outputs: [Direction] = []) {
        self.inputs = inputs
        self.outputs = outputs
    }

    /// 定義の辺(north = 正面を基準)を、向き facing に回す。
    public static func rotate(_ side: Direction, facing: Direction) -> Direction {
        var d = side
        var f = Direction.north
        while f != facing {
            d = d.clockwise
            f = f.clockwise
        }
        return d
    }
}

/// 生産モジュールの動き。
public struct ModuleRuntime: Codable, Equatable, Sendable {
    /// どのライン札から置いたか(札なしで置いた単体なら nil)。
    public var design: EntityID?
    /// このモジュールが受け持つ工程(混ぜ物・燃料の選択を含む)。工程の無い T1(採集所など)は nil。
    public var step: ProcessStep?
    /// 札の何段目か(0 始まり。並びの位置の規則「採掘口は先頭」に使う)。単体なら nil。
    public var stepIndex: Int?
    /// 入出口(向きを当てた後)。
    public var ports: ModulePorts = ModulePorts()
    /// 下にある鉱脈(採掘口)。
    public var deposit: DepositID?
    /// 入口の待ち。主の材料(物質)と、段に入れる物(燃料・混ぜ物・水)を同じ並びに持つ。
    public var input: [StockEntry] = []
    /// 出口の待ち(次へ渡す・運び出すのを待つ物)。
    public var output: [StockEntry] = []
    /// いまの 1 回の進み(ゲーム秒 × 1000。速さが掛かる)。
    public var progress: Int64 = 0
    /// 付いている仲間(配属から毎ステップ写す。表示用)。
    public var operatorID: PersonID?
    /// 1 日あたりの入出の集計(ボトルネックの表示)。
    public var today: ThroughputTally = ThroughputTally()
    public var yesterday: ThroughputTally = ThroughputTally()
    /// 置くのに使った材料(片付けると全部戻る)。
    public var paid: [StockEntry] = []
    /// 使った有限の品(旧文明系の刃など)。減ったら戻らない。
    public var finite: StockEntry?
    /// 有限の品を使ったときの来歴。
    public var finiteRecord: ProvenanceID?
    /// 止まっている理由が「来ていない」のとき、何が来ていないか。
    public var waitingFor: ItemID?
    /// 生産の来歴(1 日・入力の来歴の組ごとに 1 件。数は count にまとめる)。
    public var producedRecord: ProvenanceID?
    /// いままでに出した数。
    public var lifetimeProduced: Int = 0

    // 置いたときに定義から写す値(運搬が定義を引かずに「何をいくつ受け取るか」を決められるように)
    /// 主の材料(物質)を受け取るか(工程のあるモジュール)。採掘口・T1 は false。
    public var takesMatter: Bool = false
    /// 1 単位ごとに使う物(段に入れる燃料・混ぜ物と、T1 の使う物)。
    public var auxPerUnit: [ItemID: Int] = [:]
    /// 周りから只で取れる物(水に接していれば水)。
    public var freeItems: [ItemID] = []
    /// 入口・出口に溜めておける数。
    public var capacity: Int = 12
    /// 1 回の処理で通す数。
    public var batch: Int = 1

    public init(design: EntityID?, step: ProcessStep?) {
        self.design = design
        self.step = step
    }

    private enum CodingKeys: String, CodingKey {
        case design, step, stepIndex, ports, deposit, input, output, progress, operatorID, today, yesterday, paid
        case finite, finiteRecord, waitingFor, producedRecord, lifetimeProduced
        case takesMatter, auxPerUnit, freeItems, capacity, batch
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        design = try c.decodeIfPresent(EntityID.self, forKey: .design)
        step = try c.decodeIfPresent(ProcessStep.self, forKey: .step)
        stepIndex = try c.decodeIfPresent(Int.self, forKey: .stepIndex)
        ports = try c.decodeIfPresent(ModulePorts.self, forKey: .ports) ?? ModulePorts()
        deposit = try c.decodeIfPresent(DepositID.self, forKey: .deposit)
        input = try c.decodeIfPresent([StockEntry].self, forKey: .input) ?? []
        output = try c.decodeIfPresent([StockEntry].self, forKey: .output) ?? []
        progress = try c.decodeIfPresent(Int64.self, forKey: .progress) ?? 0
        operatorID = try c.decodeIfPresent(PersonID.self, forKey: .operatorID)
        today = try c.decodeIfPresent(ThroughputTally.self, forKey: .today) ?? ThroughputTally()
        yesterday = try c.decodeIfPresent(ThroughputTally.self, forKey: .yesterday) ?? ThroughputTally()
        paid = try c.decodeIfPresent([StockEntry].self, forKey: .paid) ?? []
        finite = try c.decodeIfPresent(StockEntry.self, forKey: .finite)
        finiteRecord = try c.decodeIfPresent(ProvenanceID.self, forKey: .finiteRecord)
        waitingFor = try c.decodeIfPresent(ItemID.self, forKey: .waitingFor)
        producedRecord = try c.decodeIfPresent(ProvenanceID.self, forKey: .producedRecord)
        lifetimeProduced = try c.decodeIfPresent(Int.self, forKey: .lifetimeProduced) ?? 0
        takesMatter = try c.decodeIfPresent(Bool.self, forKey: .takesMatter) ?? false
        auxPerUnit = try c.decodeIfPresent([ItemID: Int].self, forKey: .auxPerUnit) ?? [:]
        freeItems = try c.decodeIfPresent([ItemID].self, forKey: .freeItems) ?? []
        capacity = try c.decodeIfPresent(Int.self, forKey: .capacity) ?? 12
        batch = try c.decodeIfPresent(Int.self, forKey: .batch) ?? 1
    }

    // MARK: 受け取り・渡し(生産と運搬が同じ規則で使う)

    /// この物をあと何個受け取れるか。物質は主の材料として、物は段に入れる物として(2 回の処理ぶんまで)。
    public func room(for stuff: Stuff) -> Int {
        switch stuff {
        case .matter:
            return takesMatter ? max(0, capacity - mainInputCount) : 0
        case .item(let i):
            guard let per = auxPerUnit[i], !freeItems.contains(i) else { return 0 }
            return max(0, per * batch * 2 - inputCount(i))
        }
    }

    /// 足りていない段の物(並びは ID 順)。
    public var auxShortfall: [(item: ItemID, missing: Int)] {
        auxPerUnit.keys.sorted().compactMap { i in
            guard !freeItems.contains(i) else { return nil }
            let want = (auxPerUnit[i] ?? 0) * batch * 2
            let have = inputCount(i)
            return have < want ? (i, want - have) : nil
        }
    }

    /// 物の並びに 1 山を足す(同じ中身なら合わせる。唯一品・減る品は合わせない)。
    public static func put(_ e: StockEntry, into list: inout [StockEntry]) {
        guard e.quantity > 0 else { return }
        if e.unique == nil, e.durability == nil,
           let i = list.firstIndex(where: { $0.unique == nil && $0.durability == nil && $0.stuff == e.stuff })
        {
            list[i].quantity += e.quantity
            for (o, n) in e.origins { list[i].origins[o, default: 0] += n }
            capOrigins(&list[i])
        } else {
            list.append(e)
        }
    }

    /// 合う物を n 個まで取り出す(前の山から。来歴は多い順に按分)。取り出した山の並びを返す。
    public static func take(_ n: Int, from list: inout [StockEntry], where match: (StockEntry) -> Bool) -> [StockEntry] {
        var left = n
        var out: [StockEntry] = []
        for i in list.indices where left > 0 && match(list[i]) {
            let k = min(left, list[i].quantity)
            guard k > 0 else { continue }
            left -= k
            var piece = list[i]
            piece.quantity = k
            piece.origins = [:]
            var rest = k
            for (p, c) in list[i].origins.sorted(by: { ($0.value, $1.key) > ($1.value, $0.key) }) where rest > 0 {
                let d = min(rest, c)
                rest -= d
                piece.origins[p, default: 0] += d
                list[i].origins[p] = c - d == 0 ? nil : c - d
            }
            if rest > 0 { piece.origins[ProvenanceID(0), default: 0] += rest }
            list[i].quantity -= k
            out.append(piece)
        }
        list.removeAll { $0.quantity <= 0 }
        return out
    }

    static func capOrigins(_ e: inout StockEntry) {
        guard e.origins.count > StockEntry.originLimit else { return }
        let sorted = e.origins.sorted { ($0.value, $1.key) > ($1.value, $0.key) }
        var kept = Dictionary(uniqueKeysWithValues: sorted.prefix(StockEntry.originLimit - 1).map { ($0.key, $0.value) })
        let rest = sorted.dropFirst(StockEntry.originLimit - 1).reduce(0) { $0 + $1.value }
        kept[ProvenanceID(0), default: 0] += rest
        e.origins = kept
    }

    // MARK: 待ちの数え方

    /// 入口の物質(主の材料)の数。
    public var mainInputCount: Int {
        input.filter { if case .matter = $0.stuff { true } else { false } }.reduce(0) { $0 + $1.quantity }
    }

    /// 入口の物 item の数。
    public func inputCount(_ item: ItemID) -> Int {
        input.filter { $0.stuff == .item(item) }.reduce(0) { $0 + $1.quantity }
    }

    public var outputCount: Int { output.reduce(0) { $0 + $1.quantity } }
}

public struct ThroughputTally: Codable, Equatable, Sendable {
    /// 主の材料を使った数。
    public var consumed: Int = 0
    public var produced: Int = 0
    /// 止まっていたゲーム秒。
    public var idleSeconds: Int64 = 0
    /// 動いていたゲーム秒。
    public var runningSeconds: Int64 = 0
    /// 入口に入った数(隣から・運び手から・蓄えから)。
    public var received: Int = 0
    /// 出口から出た数(隣へ・運び手へ・蓄えへ)。
    public var sent: Int = 0

    public init() {}

    private enum CodingKeys: String, CodingKey { case consumed, produced, idleSeconds, runningSeconds, received, sent }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        consumed = try c.decodeIfPresent(Int.self, forKey: .consumed) ?? 0
        produced = try c.decodeIfPresent(Int.self, forKey: .produced) ?? 0
        idleSeconds = try c.decodeIfPresent(Int64.self, forKey: .idleSeconds) ?? 0
        runningSeconds = try c.decodeIfPresent(Int64.self, forKey: .runningSeconds) ?? 0
        received = try c.decodeIfPresent(Int.self, forKey: .received) ?? 0
        sent = try c.decodeIfPresent(Int.self, forKey: .sent) ?? 0
    }
}

/// 押し続ける手作業の途中(原作 HandCraftSession)。押している間だけ進み、1 単位ごとに入力を使って出力を出す。
public struct HandworkSession: Codable, Equatable, Sendable {
    public var id: HandworkID
    /// 入力の山(工程の手作業)。採掘・採取なら nil。
    public var input: StockSelector?
    /// 押しているか(離すと止まる。進みは残る)。
    public var holding: Bool
    /// いまの 1 単位の進み(ゲーム秒 × 1000)。
    public var progress: Int64 = 0
    /// この押し始めからできた数。
    public var done: Int = 0
    /// 押し始めた場所(足元。採掘なら鉱脈のマス)。
    public var at: WorldPoint
    /// 採掘の手作業なら、掘っている鉱脈。
    public var deposit: DepositID?

    public init(id: HandworkID, input: StockSelector?, holding: Bool, at: WorldPoint, deposit: DepositID? = nil) {
        self.id = id
        self.input = input
        self.holding = holding
        self.at = at
        self.deposit = deposit
    }
}

/// 建造物の動き(中身は建造物の種類ごと。R1: シェルター・焚き火台・柵・保管・炭焼き窯・研究机)。
public struct StructureRuntime: Codable, Equatable, Sendable {
    public var durability: Milli?
    /// 灯り・燃料などの種類ごとの値。形は RFBase の担当が決める。
    public var parameters: [String: Int] = [:]

    public init(durability: Milli? = nil) {
        self.durability = durability
    }
}
