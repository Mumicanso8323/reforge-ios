import RFContent
import RFKernel
import RFMatter
import RFWorld

/// 1 回の進行(コマンド 1 つ、またはステップ 1 回)の作業台。システムはこれを通して世界を読み書きする。
/// 共通の操作(来歴・事実・在庫・乱数・出来事)はここにしかない(誰が書いても同じ規則になるように)。
public struct StepContext {
    public var world: WorldState
    public let content: ContentDB
    /// このステップで出た出来事(本体が react に配る)。
    public private(set) var events: [DomainEvent] = []
    /// 後で処理するコマンド(効果から出た戦闘の開始など)。
    public var followUps: [Command] = []
    /// 画面の作り直しの印。
    public var changes = ChangeSet()
    /// いま適用中の効果の引き金(来歴の inputs に入る)。
    public var cause: ProvenanceID?
    /// 仕組みがまだ無い効果など、黙って捨てたくないもの(テストが 0 件を確かめる)。
    public var warnings: [String] = []

    public init(world: WorldState, content: ContentDB) {
        self.world = world
        self.content = content
    }

    // MARK: 出来事

    public mutating func emit(_ e: DomainEvent) { events.append(e) }

    /// 本体が配り終えた出来事を取り出す。
    public mutating func drainEvents() -> [DomainEvent] {
        defer { events.removeAll() }
        return events
    }

    public mutating func queue(_ c: Command) { followUps.append(c) }

    // MARK: 乱数

    public mutating func random<T>(_ stream: RandomStreamID, _ body: (inout SeededRandom) -> T) -> T {
        world.rng.use(stream, body)
    }

    // MARK: 来歴

    /// 来歴を 1 件残す。inputs に cause(効果の引き金)を自動で足す。
    @discardableResult
    public mutating func record(_ act: ActKind, _ subject: SubjectRef, actor: PersonID? = nil, place: WorldPoint? = nil,
                                inputs: [ProvenanceID] = [], tags: Set<ProvenanceTag> = [],
                                detail: [String: Value] = [:]) -> ProvenanceID
    {
        let now = world.clock.now
        let day = world.clock.day
        let run = world.run.index
        var ins = inputs
        if let c = cause, !ins.contains(c) { ins.append(c) }
        return world.ledger.append {
            ProvenanceRecord(id: $0, at: now, day: day, run: run, actor: actor, act: act, subject: subject,
                             place: place, inputs: ins, tags: tags, detail: detail)
        }
    }

    // MARK: 事実

    /// 事実を知る(含意する事実も)。知っている事実が変わると、見え方を全部引き直す印を付ける。
    public mutating func learn(_ fact: FactID, via: ProvenanceID? = nil) {
        var queue = [fact]
        while let f = queue.popLast() {
            guard world.knowledge.facts[f] == nil else { continue }
            let rec = record(.learned, .fact(f), inputs: via.map { [$0] } ?? [])
            world.knowledge.facts[f] = FactRecord(learnedAt: world.clock.now, run: world.run.index, via: via ?? rec)
            emit(.factLearned(fact: f, record: rec))
            changes.mark(.perception)
            queue += content.facts[f]?.implies ?? []
        }
    }

    // MARK: 在庫

    /// 物を入れる(同じ中身の山があれば合わせる。唯一品は合わせない)。
    public mutating func addStock(_ stuff: Stuff, _ n: Int, to holder: HolderID, origin: ProvenanceID? = nil,
                                  unique: EntityID? = nil)
    {
        guard n > 0 else { return }
        var list = world.inventory.holders[holder] ?? []
        let o = origin ?? ProvenanceLedger.unknownOrigin
        if unique == nil, let i = list.firstIndex(where: { $0.unique == nil && $0.stuff == stuff }) {
            list[i].quantity += n
            list[i].origins[o, default: 0] += n
            Self.capOrigins(&list[i])
        } else {
            list.append(StockEntry(stuff: stuff, quantity: n, origins: [o: n], unique: unique))
        }
        world.inventory.holders[holder] = list
        changes.mark(.inventory)
        emit(.itemGained(holder: holder, stuff: stuff, quantity: n, record: origin))
    }

    /// 合う物を n 個取り出す。足りなければ何もせず nil。取り出した物の来歴(数つき)を返す。
    public mutating func takeStock(_ n: Int, from holder: HolderID, where match: (StockEntry) -> Bool)
        -> [ProvenanceID: Int]?
    {
        var list = world.inventory.holders[holder] ?? []
        let have = list.filter(match).reduce(0) { $0 + $1.quantity }
        guard n > 0, have >= n else { return n == 0 ? [:] : nil }
        var left = n
        var took: [ProvenanceID: Int] = [:]
        for i in list.indices where left > 0 && match(list[i]) {
            let k = min(left, list[i].quantity)
            left -= k
            list[i].quantity -= k
            // 来歴は多い順に按分して減らす(決定的に)
            var rest = k
            for (p, c) in list[i].origins.sorted(by: { ($0.value, $1.key) > ($1.value, $0.key) }) where rest > 0 {
                let d = min(rest, c)
                rest -= d
                took[p, default: 0] += d
                list[i].origins[p] = c - d == 0 ? nil : c - d
            }
            emit(.itemSpent(holder: holder, stuff: list[i].stuff, quantity: k))
        }
        list.removeAll { $0.quantity <= 0 }
        world.inventory.holders[holder] = list
        changes.mark(.inventory)
        return took
    }

    static func capOrigins(_ e: inout StockEntry) {
        guard e.origins.count > StockEntry.originLimit else { return }
        let sorted = e.origins.sorted { ($0.value, $1.key) > ($1.value, $0.key) }
        var kept = Dictionary(uniqueKeysWithValues: sorted.prefix(StockEntry.originLimit - 1).map { ($0.key, $0.value) })
        let rest = sorted.dropFirst(StockEntry.originLimit - 1).reduce(0) { $0 + $1.value }
        kept[ProvenanceLedger.unknownOrigin, default: 0] += rest
        e.origins = kept
    }
}

extension Ingredient {
    /// 在庫の山がこの材料に合うか。
    public func matches(_ e: StockEntry) -> Bool {
        switch e.stuff {
        case .item(let i): item == i && matter == nil
        case .matter(let m): matter?.matches(m) ?? false
        }
    }
}
