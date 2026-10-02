import RFBase
import RFContent
import RFKernel
import RFMap
import RFPerception
import RFResearch
import RFRules
import RFSim
import RFWorld

// 拠点・仲間・研究・戦闘の射影と、画面の要素の解放(U18)。文字はすべて認識の層を通した後のもの。
// 固定の見出し(「蓄え」「割り当て」など)は画面の Localizable が持つ。ここは種類(enum)と名前だけを渡す。

// MARK: - 解放

/// 画面の要素の解放の状態(Frame.ui)。表(ContentDB.uiGates)に無い要素はいつも出す。
public struct UIUnlocks: Equatable, Sendable {
    /// 条件の付いた要素。
    public var gated: Set<UIElementID>
    /// 条件の付いた要素のうち、いま成り立っているもの。
    public var open: Set<UIElementID>

    public init(gated: Set<UIElementID> = [], open: Set<UIElementID> = []) {
        self.gated = gated
        self.open = open
    }

    public func isOpen(_ id: UIElementID) -> Bool { !gated.contains(id) || open.contains(id) }

    /// 要素の ID の一覧(RFContent.UIElements と同じもの)。
    public typealias Element = UIElements
}

extension FrameBuilder {
    /// 導出するタブと、その配下の要素(ID の頭)。
    static let tabChildren: [(UIElementID, (UIElementID) -> Bool)] = [
        (UIElements.tabBase, { $0.rawValue.hasPrefix("base.") || $0 == UIElements.research }),
        (UIElements.tabCrew, { $0.rawValue.hasPrefix("crew.") }),
        (UIElements.tabDesign, { $0.rawValue.hasPrefix("design.") }),
        (UIElements.tabNotes, { $0.rawValue.hasPrefix("notes.") }),
    ]

    /// 条件の付いた要素を評価する(乱数を進めない)。
    public func unlocks(_ w: WorldState) -> UIUnlocks {
        var u = UIUnlocks(gated: Set(content.uiGates.keys))
        for (id, g) in content.uiGates {
            // 開いたままの記録(W-01)があるか、いま条件が成り立てば開く
            if w.knowledge.disclosed[id] != nil
                || ConditionEvaluator.evaluatePure(g.when, world: w, content: content) == true {
                u.open.insert(id)
            }
        }
        // タブは導出(W-01): 自分の門が無く、配下に latch 付きの門(新しい形のデータ)があれば、
        // 配下のどれかが開いたときだけ開く。配下に latch の無い門しか無い古いデータでは今までどおり常に出る
        for (tab, under) in Self.tabChildren where content.uiGates[tab] == nil {
            let gatedChildren = u.gated.filter(under)
            guard gatedChildren.contains(where: { content.uiGates[$0]?.latch != nil }) else { continue }
            u.gated.insert(tab)
            if !gatedChildren.isDisjoint(with: u.open) { u.open.insert(tab) }
        }
        return u
    }
}

// MARK: - 戦闘

/// 進行中の戦闘 1 つ(上の帯と地図に出す。止めない)。
public struct BattleBand: Equatable, Sendable {
    public struct Unit: Equatable, Sendable {
        public var glyph: String
        public var isAlly: Bool
        /// 帯の上の位置(0...laneSize-1)。
        public var position: Int
        /// 体力(千分率)。
        public var hpPermille: Int
        public var active: Bool

        public init(glyph: String, isAlly: Bool, position: Int, hpPermille: Int, active: Bool) {
            self.glyph = glyph
            self.isAlly = isAlly
            self.position = position
            self.hpPermille = hpPermille
            self.active = active
        }
    }

    public var id: EntityID
    /// 相手の名前(認識の層)。
    public var foe: String
    public var stance: BattleState.Stance
    public var retreating: Bool
    public var laneSize: Int
    public var at: GridPoint
    public var units: [Unit]

    public init(id: EntityID, foe: String, stance: BattleState.Stance, retreating: Bool, laneSize: Int, at: GridPoint,
                units: [Unit]) {
        self.id = id
        self.foe = foe
        self.stance = stance
        self.retreating = retreating
        self.laneSize = laneSize
        self.at = at
        self.units = units
    }

    public func stanceCommand(_ s: BattleState.Stance) -> Command { .combat(.stance(battle: id, stance: s)) }
    public var retreatCommand: Command { .combat(.retreat(battle: id)) }
}

extension FrameBuilder {
    func battles(_ w: WorldState, _ p: Perceiver) -> [BattleBand] {
        w.combat.battles.keys.sorted().compactMap { id in
            guard let b = w.combat.battles[id], b.outcome == nil else { return nil }
            var foe = p.text(Perceiver.unknownText)
            let units = b.units.map { u -> BattleBand.Unit in
                let g: String
                switch u.ref {
                case .person(let pid): g = pid == .noah ? "@" : p.glyph(Subject.person(pid))
                case .enemy(_, let kind, _):
                    g = p.glyph(Subject.enemy(kind))
                    foe = p.name(Subject.enemy(kind))
                }
                return BattleBand.Unit(glyph: g, isAlly: u.side == .allies, position: u.position,
                                       hpPermille: u.maxHP > 0 ? max(0, u.hp) * 1000 / u.maxHP : 0,
                                       active: u.state == .active)
            }
            return BattleBand(id: id, foe: foe, stance: b.stance, retreating: b.retreating, laneSize: b.laneSize,
                              at: b.at.point, units: units)
        }
    }
}

// MARK: - 拠点

public struct BaseView: Equatable, Sendable {
    public struct StockLine: Equatable, Sendable {
        public var name: String
        public var quantity: Int
    }

    public struct Built: Equatable, Sendable {
        public enum State: Equatable, Sendable {
            case running
            /// 建造中(進み 0...1000)。
            case building(permille: Int)
            case stopped(reason: String)
            case broken
        }

        public var id: EntityID
        public var name: String
        public var glyph: String
        public var at: WorldPoint
        public var state: State
        /// 付いて働いている人の名前。
        public var workers: [String]
        /// 研究机か(研究の割り当て先)。
        public var isResearch: Bool
    }

    public struct BuildOption: Equatable, Sendable {
        public var kind: StructureKindID
        public var name: String
        public var glyph: String
        public var cost: [StockLine]
        /// いまの蓄えで足りるか(足りなくても選べる。置くときに本体が断る)。
        public var affordable: Bool
    }

    public struct Line: Equatable, Sendable {
        public var id: EntityID
        public var from: String
        public var to: String
        public var haulers: [String]
        public var movedYesterday: Int
        public var movedToday: Int
        public var blocked: String?
    }

    public var stock: [StockLine]
    public var built: [Built]
    public var buildable: [BuildOption]
    public var lines: [Line]
    /// まだ解禁されていない建造物の数(建てる一覧の「？」。名前は出さない。§10 HNT-13)。
    public var unknownStructures: Int = 0
}

extension FrameBuilder {
    public func base(_ w: WorldState) -> BaseView {
        let p = Perceiver(content: content, world: w)
        var stock: [String: Int] = [:]
        var order: [String] = []
        for e in w.inventory.entries(.base) {
            let n = p.name(of: e.stuff)
            if stock[n] == nil { order.append(n) }
            stock[n, default: 0] += e.quantity
        }
        let names = { (ids: [PersonID]) in ids.map { p.name(Subject.person($0)) } }
        let built = w.placements.sortedIDs.compactMap { id -> BaseView.Built? in
            guard let pl = w.placements.items[id] else { return nil }
            let s = Perceiver.subject(of: pl.kind)
            let state: BaseView.Built.State = switch pl.status {
            case .running: .running
            case .underConstruction(let pr): .building(permille: buildPermille(pl, pr))
            case .stopped(let r): .stopped(reason: p.text(r))
            case .broken: .broken
            }
            var research = false
            if case .structure(let k) = pl.kind { research = (content.structures[k]?.provides["research"] ?? 0) > 0 }
            return BaseView.Built(id: id, name: p.name(s), glyph: p.glyph(s), at: pl.at, state: state,
                                  workers: names(w.people.workers(at: id)), isResearch: research)
        }
        let buildable = w.research.unlocked.structures.sorted().compactMap { k -> BaseView.BuildOption? in
            guard let d = content.structures[k] else { return nil }
            let cost = d.cost.map { BaseView.StockLine(name: ingredientName($0, p), quantity: $0.quantity) }
            let ok = d.cost.allSatisfy { ConditionEvaluator.evaluatePure(.has(what: $0), world: w, content: content) == true }
            return BaseView.BuildOption(kind: k, name: p.name(Subject.structure(k)), glyph: p.glyph(Subject.structure(k)),
                                        cost: cost, affordable: ok)
        }
        let lines = w.logistics.sortedRouteIDs.compactMap { id -> BaseView.Line? in
            guard let r = w.logistics.routes[id] else { return nil }
            return BaseView.Line(id: id, from: endpointName(r.from, w, p), to: endpointName(r.to, w, p),
                                 haulers: names(w.people.haulers(of: id)), movedYesterday: r.movedYesterday,
                                 movedToday: r.movedToday, blocked: r.blocked.map { p.text($0) })
        }
        return BaseView(stock: order.map { BaseView.StockLine(name: $0, quantity: stock[$0] ?? 0) }, built: built,
                        buildable: buildable, lines: lines,
                        unknownStructures: content.structures.keys.filter { !w.research.unlocked.structures.contains($0) }.count)
    }

    func buildPermille(_ pl: Placement, _ progress: Int) -> Int {
        guard case .structure(let k) = pl.kind, let d = content.structures[k], d.buildSeconds > 0 else { return 0 }
        return min(1000, max(0, progress * 1000 / d.buildSeconds))
    }

    func ingredientName(_ i: Ingredient, _ p: Perceiver) -> String {
        i.item.map { p.name(Subject.item($0)) } ?? p.text(Perceiver.unknownText)
    }

    func endpointName(_ e: HaulEndpoint, _ w: WorldState, _ p: Perceiver) -> String {
        switch e {
        case .base: p.text("text.base.stock")
        case .placement(let id): w.placements.items[id].map { p.name(of: $0.kind) } ?? p.text(Perceiver.unknownText)
        }
    }
}

// MARK: - 仲間

public struct CrewMemberView: Equatable, Sendable {
    /// 割り当ての種類(画面の固定文言はこれで引く)。
    public enum AssignKind: String, Equatable, Sendable, CaseIterable {
        case idle, gather, haul, operate, research, guardArea = "guard", build, rest, follow
    }

    public enum Doing: String, Equatable, Sendable {
        case idle, walking, working, carrying, gathering, fighting, sleeping, talking, guarding
    }

    public struct Body: Equatable, Sendable {
        /// 千分率(100 点満点の体の値 → 0...1000)。
        public var health: Int
        public var stamina: Int
        public var satiety: Int
        public var hydration: Int
        public var mind: Int
        /// 状態の名前(負傷・病気…)。
        public var conditions: [String]
    }

    public var id: PersonID
    public var name: String
    public var glyph: String
    public var isNoah: Bool
    public var assignment: AssignKind
    /// 割り当て先の名前(炉・経路…)。
    public var target: String?
    public var doing: Doing
    public var body: Body
    public var relationRank: Int
    /// いまのランクの中の点と、次のランクまでの点。
    public var relationPoints: Int
    public var relationNext: Int
    /// 出来事が配属を上書きしている(本人の割り当てに従っていない)。
    public var overridden: Bool
    /// 立ち絵(無ければ枠ごと出さない)。
    public var art: ArtID? = nil
}

/// 割り当ての選択肢 1 つ(どの一員にも同じ並びで出す)。
public struct AssignChoice: Equatable, Sendable {
    public var kind: CrewMemberView.AssignKind
    /// 対象の名前(無い種類は nil)。
    public var target: String?
    public var assignment: Assignment

    public func command(for person: PersonID) -> Command { .crew(.assign(person: person, assignment: assignment)) }
}

public struct CrewView: Equatable, Sendable {
    public var members: [CrewMemberView]
    public var choices: [AssignChoice]
}

extension FrameBuilder {
    /// 仲間の表(拠点の一員。ノアが先頭)と、割り当ての選択肢。
    public func crew(_ w: WorldState) -> CrewView {
        let p = Perceiver(content: content, world: w)
        let researchDesks = Set(w.placements.sortedIDs.filter { id in
            guard case .structure(let k)? = w.placements.items[id]?.kind else { return false }
            return (content.structures[k]?.provides["research"] ?? 0) > 0
        })
        func pct(_ m: Milli) -> Int { Int(max(0, min(100_000, m.raw)) / 100) }
        let members = w.people.members.compactMap { id -> CrewMemberView? in
            guard let ps = w.people[id] else { return nil }
            let a = w.people.effectiveAssignment(id) ?? .idle
            let (kind, target) = describe(a, w, p, researchDesks)
            return CrewMemberView(
                id: id, name: p.name(Subject.person(id)), glyph: id == .noah ? "@" : p.glyph(Subject.person(id)),
                isNoah: id == .noah, assignment: kind, target: target, doing: doing(ps.activity),
                body: .init(health: pct(ps.body.health), stamina: pct(ps.body.stamina), satiety: pct(ps.body.satiety),
                            hydration: pct(ps.body.hydration), mind: pct(ps.body.mind),
                            conditions: ps.body.conditions.keys.sorted().filter { (ps.body.conditions[$0] ?? 0) > 0 }
                                .map { p.name(Subject.stat($0)) }),
                relationRank: ps.relation.rank, relationPoints: ps.relation.points,
                relationNext: RelationState.threshold(rank: ps.relation.rank), overridden: ps.override != nil,
                art: p.art(Subject.person(id)))
        }
        return CrewView(members: members, choices: assignChoices(w, p, researchDesks))
    }

    func describe(_ a: Assignment, _ w: WorldState, _ p: Perceiver, _ desks: Set<EntityID>)
        -> (CrewMemberView.AssignKind, String?)
    {
        let placed = { (e: EntityID) in w.placements.items[e].map { p.name(of: $0.kind) } }
        switch a {
        case .idle: return (.idle, nil)
        case .rest: return (.rest, nil)
        case .gather(let i, _): return (.gather, p.name(PresentSubject.interaction(i)))
        case .haul(let r):
            let route = w.logistics.routes[r]
            return (.haul, route.map { "\(endpointName($0.from, w, p))→\(endpointName($0.to, w, p))" })
        case .operate(let e): return (desks.contains(e) ? .research : .operate, placed(e))
        case .guardArea: return (.guardArea, nil)
        case .build(let e): return (.build, placed(e))
        case .follow(let o): return (.follow, p.name(Subject.person(o)))
        case .tendHearth(let e): return (.operate, placed(e))
        }
    }

    func doing(_ a: Activity) -> CrewMemberView.Doing {
        switch a {
        case .idle: .idle
        case .walking: .walking
        case .working: .working
        case .carrying: .carrying
        case .interacting: .gathering
        case .fighting: .fighting
        case .sleeping: .sleeping
        case .talking: .talking
        case .guarding, .interposing: .guarding
        }
    }

    /// 割り当ての選択肢。種類の順(採取・運搬・炉などの持ち場・研究・見張り・建造・休む・空き)。
    /// 採取は、見つけた鉱脈と既知の POI のうち拠点(無ければノア)に近いものから最大 4 か所。
    func assignChoices(_ w: WorldState, _ p: Perceiver, _ desks: Set<EntityID>) -> [AssignChoice] {
        var out: [AssignChoice] = []
        let layer = LayerID.surface
        let center: GridPoint? = w.base.area.map { GridPoint($0.origin.x + $0.size.width / 2, $0.origin.y + $0.size.height / 2) }
            ?? w.people[.noah]?.position?.point
        // 採取
        let proj = MapProjector(world: w, content: content, perceiver: p, layer: layer)
        var spots: [(GridPoint, InteractionID)] = []
        for (pt, d) in proj.depositAt where d.deposit.isDiscovered && d.deposit.remainingExtractions > 0 {
            for (id, def) in content.interactions where def.target == .deposit { spots.append((pt, id)) }
        }
        for (pt, poi) in proj.poiAt where proj.isKnown(pt) {
            for (id, def) in content.interactions where def.target == .poi(kind: poi.poi.kind) { spots.append((pt, id)) }
        }
        let dist = { (a: GridPoint) in center.map { abs($0.x - a.x) + abs($0.y - a.y) } ?? 0 }
        spots.sort { (dist($0.0), $0.0.y, $0.0.x, $0.1) < (dist($1.0), $1.0.y, $1.0.x, $1.1) }
        var seen = Set<GridPoint>()
        for (pt, id) in spots where seen.insert(pt).inserted && seen.count <= 4 {
            if let c = content.interactions[id]?.when, ConditionEvaluator.evaluatePure(c, world: w, content: content) != true {
                continue
            }
            out.append(AssignChoice(kind: .gather, target: p.name(PresentSubject.interaction(id)),
                                    assignment: .gather(interaction: id, at: WorldPoint(layer, pt))))
        }
        // 運搬
        for id in w.logistics.sortedRouteIDs {
            guard let r = w.logistics.routes[id] else { continue }
            out.append(AssignChoice(kind: .haul, target: "\(endpointName(r.from, w, p))→\(endpointName(r.to, w, p))",
                                    assignment: .haul(route: id)))
        }
        // 持ち場(モジュール)・研究机
        for id in w.placements.sortedIDs {
            guard let pl = w.placements.items[id] else { continue }
            if case .underConstruction = pl.status {
                out.append(AssignChoice(kind: .build, target: p.name(of: pl.kind), assignment: .build(placement: id)))
            } else if desks.contains(id) {
                out.append(AssignChoice(kind: .research, target: p.name(of: pl.kind), assignment: .operate(placement: id)))
            } else if pl.module != nil {
                out.append(AssignChoice(kind: .operate, target: p.name(of: pl.kind), assignment: .operate(placement: id)))
            }
        }
        // 見張り(拠点の真ん中)
        if let c = center {
            out.append(AssignChoice(kind: .guardArea, target: nil, assignment: .guardArea(center: WorldPoint(layer, c), radius: 4)))
        }
        out.append(AssignChoice(kind: .rest, target: nil, assignment: .rest))
        out.append(AssignChoice(kind: .idle, target: nil, assignment: .idle))
        // 研究机が先に並ぶように種類で安定に並べ替える
        let rank = { (k: CrewMemberView.AssignKind) in CrewMemberView.AssignKind.order.firstIndex(of: k) ?? 99 }
        return out.enumerated().sorted { (rank($0.element.kind), $0.offset) < (rank($1.element.kind), $1.offset) }.map(\.element)
    }
}

extension CrewMemberView.AssignKind {
    /// 画面に並べる順。
    public static let order: [Self] = [.gather, .haul, .operate, .research, .guardArea, .build, .rest, .idle, .follow]
}

// MARK: - 研究

public struct ResearchView: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        public var id: ResearchID
        public var name: String
        public var status: ResearchQueries.Status
        public var points: Int
        public var totalPoints: Int

        public var selectCommand: Command { .research(.select(research: id)) }
    }

    public var entries: [Entry]
    /// いま研究を進めている人の名前。
    public var studying: [String]
    /// 研究机があるか(無ければ選んでも進まない)。
    public var hasDesk: Bool
    /// まだ見えていない研究の数(「この先にまだ n 件」。名前は出さない。§10 HNT-16)。
    public var hiddenCount: Int = 0
}

extension FrameBuilder {
    public func research(_ w: WorldState) -> ResearchView {
        let p = Perceiver(content: content, world: w)
        let entries = ResearchQueries.list(w, content).map {
            ResearchView.Entry(id: $0.id, name: p.name(Subject.research($0.id)), status: $0.status, points: $0.points,
                               totalPoints: $0.totalPoints)
        }
        let desk = w.placements.items.values.contains { pl in
            guard case .structure(let k) = pl.kind, pl.status == .running else { return false }
            return (content.structures[k]?.provides["research"] ?? 0) > 0
        }
        let hidden = content.research.values.filter { !ResearchRules.isVisible($0, w, content) }.count
        return ResearchView(entries: entries, studying: w.research.studying.map { p.name(Subject.person($0)) },
                            hasDesk: desk, hiddenCount: hidden)
    }
}

// MARK: - 置くモードの照準

/// 置くモードの照準(地図に、置けるなら緑・置けないなら赤で描く)。
public struct PlacementPreview: Equatable, Sendable {
    public var kind: StructureKindID
    public var at: GridPoint
    /// 占めるマス。
    public var cells: [GridPoint]
    public var placeable: Bool
    /// 置けない理由(認識の層を通した 1 行)。
    public var reason: String?

    public init(kind: StructureKindID, at: GridPoint, cells: [GridPoint], placeable: Bool, reason: String?) {
        self.kind = kind
        self.at = at
        self.cells = cells
        self.placeable = placeable
        self.reason = reason
    }

    public var buildCommand: Command { .base(.build(structure: kind, at: WorldPoint(.surface, at), facing: Self.facing)) }
    /// 回転は後回し(いまは南向き固定)。
    public static let facing: Direction = .south
}

extension FrameBuilder {
    public func placementPreview(_ w: WorldState, kind: StructureKindID, at pt: GridPoint) -> PlacementPreview {
        let fp = BaseQueries.footprint(kind, facing: PlacementPreview.facing, content: content)
        let r = BaseQueries.siteRejection(kind, at: WorldPoint(layer, pt), facing: PlacementPreview.facing, world: w,
                                          content: content)
        return PlacementPreview(kind: kind, at: pt, cells: fp.map { pt + $0 }, placeable: r == nil,
                                reason: r.map { Perceiver(content: content, world: w).text($0.reason) })
    }
}
