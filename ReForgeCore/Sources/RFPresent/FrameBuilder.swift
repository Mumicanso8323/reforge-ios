import RFContent
import RFExploration
import RFKernel
import RFMap
import RFMatter
import RFPerception
import RFRules
import RFInvention
import RFSim
import RFWorld

/// 世界状態 → Frame(と、区画・調べる・足元カード・工程表などの引き出し)。持ち主: U13 画面。
public struct FrameBuilder: Sendable {
    public let content: ContentDB
    public var vision = VisionRadiusRule()
    /// 描く層(地下は R2)。
    public var layer: LayerID = .surface

    public init(content: ContentDB) { self.content = content }

    // MARK: - Frame

    /// - previous: 前の Frame(区画の版を引き継ぐ)。nil なら全区画を revision にする(新しい世界・ロード)。
    /// - report: 進行の結果。知っている事実が変わった(perception)なら全区画、変わったマス(dirtyTiles)の区画を上げる。
    ///   それとは別に、区画の中身の指紋を前の Frame と比べ、変わった区画を上げる(他の担当が印を付け忘れても描き直す)。
    public func build(_ w: WorldState, revision: Int, previous: Frame?, report: StepReport?) -> Frame {
        let p = Perceiver(content: content, world: w)
        let proj = MapProjector(world: w, content: content, perceiver: p, layer: layer)
        let size = proj.size
        var map = MapView(layer: layer, size: size, chunkRevisions: [], vision: vision.areas(w, layer: layer))
        map.beacons = w.exploration.beacons.sorted { $0.key < $1.key }.compactMap { $0.value.layer == layer ? $0.value.point : nil }
        let count = map.chunkColumns * map.chunkRows
        let signatures = (0..<count).map { proj.signature(map.chunkRect($0)) }
        var revs: [Int]
        if let prev = previous?.map, prev.size == size, prev.layer == layer, prev.chunkRevisions.count == count {
            revs = prev.chunkRevisions
            let all = report?.changes.areas.contains(.perception) == true
            for i in 0..<count where all || i >= prev.chunkSignatures.count || prev.chunkSignatures[i] != signatures[i] {
                revs[i] = revision
            }
            for t in report?.changes.dirtyTiles ?? [] where t.layer == layer {
                if let i = map.chunkIndex(of: t.point) { revs[i] = revision }
            }
        } else {
            revs = Array(repeating: revision, count: count)
        }
        map.chunkRevisions = revs
        map.chunkSignatures = signatures

        let noah = w.people[.noah]
        let noahPos = noah?.position.flatMap { $0.layer == layer ? $0.point : nil }
        var frame = Frame(
            revision: revision,
            clock: clockView(w),
            status: statusItems(w, p),
            objective: objective(w, p),
            map: map,
            actors: actors(w, p, map: map),
            placements: placements(w, p, proj: proj, map: map),
            route: noahPos == nil ? [] : (noah?.motion?.path ?? []),
            focus: noahPos,
            decision: decision(w, p),
            sceneLines: sceneLines(w, p),
            notices: [],
            renamed: [],
            runEnded: !w.run.isActive)
        frame.ui = unlocks(w)
        // 帯の要素の門(U20。門の無い古いデータでは全部出る)
        frame.clock.showsDayLeft = !w.clock.held && frame.ui.isOpen(UIElements.bandDay)
        if !frame.ui.isOpen(UIElements.bandObjective) { frame.objective = nil }
        frame.status = frame.status.filter { item in
            content.stats[StatID(item.key)]?.band.map { frame.ui.isOpen($0) } ?? true
        }
        frame.placeTitle = content.perception[Self.placeSubject] == nil ? nil : p.name(Self.placeSubject)
        frame.newlyOpened = previous.map { frame.ui.open.subtracting($0.ui.open) } ?? []
        frame.shadows = shadows(w, p)
        frame.battles = battles(w, p)
        frame.defaultStance = w.combat.defaultStance
        if w.clock.phase == .dusk { frame.dayWrap = dayWrap(w) }
        frame.benchRevision = Self.benchRevision(previous: previous, report: report, revision: revision, day: w.clock.day)
        if let prologue = prologue(w, p) {
            frame.prologue = prologue
            frame.status = []
            frame.objective = nil
            frame.map.vision = []
            frame.map.beacons = []
            frame.map.chunkRevisions = Array(repeating: revision, count: frame.map.chunkRevisions.count)
            frame.map.chunkSignatures = Array(repeating: -1, count: frame.map.chunkSignatures.count)
            frame.actors = []
            frame.placements = []
            frame.route = []
            frame.focus = nil
            frame.decision = nil
            frame.sceneLines = []
            frame.battles = []
            frame.ui = UIUnlocks(gated: Set(UIElements.all), open: [])
            frame.newlyOpened = []
            frame.shadows = []
            frame.dayWrap = nil
        } else {
            frame.darkStart = darkStart(w)
            if frame.darkStart == nil { applySteering(&frame, w) }
        }
        return frame
    }

    /// 操作棒を出してよいか(地図が灯っていて、戦闘中・眠っている間ではない)と、歩ける範囲を Frame に書く。
    func applySteering(_ frame: inout Frame, _ w: WorldState) {
        guard w.run.isActive, !w.clock.held, !w.clock.sleeping,
              let noah = w.people[.noah], noah.presence.isAlive, let pos = noah.position, pos.layer == layer else { return }
        if case .fighting(let battle) = noah.activity, w.combat.battles[battle] != nil { return }
        frame.canSteer = true
        frame.walkable = WalkRange.rowSpans(WalkRange.circles(w, content: content, layer: layer))
            .map { WalkSpan(y: $0.y, minX: $0.minX, maxX: $0.maxX) }
    }

    /// 地図の題の主題(INV-O12)。
    public static let placeSubject: SubjectID = "place:base"

    /// 半分の気配の影の行(W-07)。まだ解放されていない建造物・モジュールを ID 順に。
    public func shadows(_ w: WorldState, _ p: Perceiver) -> [ShadowRow] {
        func row(_ kind: PlaceableKind, _ cost: [Ingredient]) -> ShadowRow? {
            guard HintRule.halfway(cost: cost, world: w) else { return nil }
            let have = cost.reduce(0) { $0 + min(ConditionEvaluator.stockCount($1, w), $1.quantity) }
            return ShadowRow(kind: kind, name: p.name(of: kind), have: have,
                             need: cost.reduce(0) { $0 + $1.quantity })
        }
        let s = content.structures.keys.sorted().filter { !w.research.unlocked.structures.contains($0) }
            .compactMap { row(.structure($0), content.structures[$0]!.cost) }
        let m = content.modules.keys.sorted().filter { !w.research.unlocked.modules.contains($0) }
            .compactMap { row(.module($0), content.modules[$0]!.cost) }
        return s + m
    }

    /// 設計・ノートのタブが引き直す印。在庫・ノート・知識・研究・物語が変わったとき、日が変わったときに上がる。
    static let benchAreas: ChangeSet.Areas = [.inventory, .notebook, .perception, .research, .narrative, .placements]

    static func benchRevision(previous: Frame?, report: StepReport?, revision: Int, day: Int) -> Int {
        guard let prev = previous, let report else { return revision }
        if !report.changes.areas.isDisjoint(with: benchAreas) || prev.clock.day != day { return revision }
        return prev.benchRevision
    }

    func clockView(_ w: WorldState) -> ClockView {
        let dayLen = content.clock.dayGameSeconds
        let since = (w.clock.now - w.clock.dayStartedAt).seconds
        let readingStage = w.narrative.scene.flatMap { content.scenes[$0.scene] }?.style == .stage
        var v = ClockView(
            day: w.clock.day, phase: w.clock.phase,
            dayRemainingPermille: w.clock.phase == .day && dayLen > 0 ? Int(max(0, (dayLen - since) * 1000 / dayLen)) : 0,
            running: w.run.isActive && w.clock.phase == .day && !w.clock.held
                && !w.narrative.pending.contains(where: \.blocking) && !readingStage)
        v.held = w.clock.held
        v.fireOutlook = duskFireOutlook(w)
        return v
    }

    func statusItems(_ w: WorldState, _ p: Perceiver) -> [StatusItem] {
        // 赤の判定は生存の担当が StatDef に足す(alertBelow など)。入ったらここで写す。
        let unknown = p.text(Perceiver.unknownText)
        return w.survival.stats.keys.sorted().compactMap { id -> StatusItem? in
            guard let value = p.stat(id, value: w.survival.stats[id] ?? .zero), !value.isEmpty else { return nil }
            let label = p.name(Subject.stat(id))
            guard !label.isEmpty, label != unknown else { return nil }
            var item = StatusItem(key: id.rawValue, label: label, value: value, alert: false)
            if p.variant(Subject.stat(id))?.showMarks == true, let marks = content.stats[id]?.marks {
                item.gauge = StatGauge.make(value: (w.survival.stats[id] ?? .zero).raw, marks: marks)
            }
            return item
        }
    }

    func objective(_ w: WorldState, _ p: Perceiver) -> String? {
        w.narrative.objectives.keys.sorted().first { w.narrative.objectives[$0] == .active && content.objectives[$0] != nil }
            .flatMap { content.objectives[$0].map { p.text($0.text) } }
    }

    func actors(_ w: WorldState, _ p: Perceiver, map: MapView) -> [ActorSprite] {
        w.people.order.compactMap { id -> ActorSprite? in
            guard let ps = w.people[id], ps.presence.isAlive, let pos = ps.position, pos.layer == layer else { return nil }
            let member = ps.presence.isMember
            if case .unmet = ps.presence { return nil }
            // 一員は視界の外でも描く。それ以外(会った人)は視界の中だけ。
            if !member, !map.isVisible(pos.point) { return nil }
            let isNoah = id == .noah
            let next = ps.motion?.path.first ?? pos.point
            return ActorSprite(id: id.rawValue, glyph: isNoah ? TilePalette.noahGlyph : (member ? TilePalette.memberGlyph : p.glyph(Subject.person(id))),
                               from: pos.point, to: next, progress: ps.motion?.progress ?? 0, facing: ps.facing,
                               label: p.name(Subject.person(id)), isNoah: isNoah, isMember: member,
                               tint: isNoah ? TilePalette.noah : (member ? TilePalette.member : TilePalette.stranger))
        }
    }

    /// 置いた物は、既知か視界の中のマスにあるものだけ。暗がりの印だけは未踏でも見える。
    func placements(_ w: WorldState, _ p: Perceiver, proj: MapProjector, map: MapView) -> [PlacementSprite] {
        w.placements.sortedIDs.compactMap { id in
            guard let pl = w.placements.items[id], pl.at.layer == layer else { return nil }
            let seenInDark: Bool = if case .structure(let kind) = pl.kind {
                content.structures[kind]?.seenInDark ?? false
            } else {
                false
            }
            guard proj.isKnown(pl.at.point) || map.isVisible(pl.at.point) || seenInDark,
                  !(seenInDark && pl.destroyedBy != nil) else { return nil }
            let s: SubjectID = switch pl.kind {
            case .module(let k): Subject.module(k)
            case .structure(let k): Subject.structure(k)
            }
            var reason: String?
            if case .stopped(let r) = pl.status { reason = p.text(r) }
            return PlacementSprite(id: id, glyph: p.glyph(s), at: pl.at.point, facing: pl.facing,
                                   running: pl.status == .running, stoppedReason: reason, throughput: nil,
                                   seenInDark: seenInDark)
        }
    }

    func decision(_ w: WorldState, _ p: Perceiver) -> DecisionView? {
        w.narrative.pending.first.map { d in
            DecisionView(id: d.id, blocking: d.blocking, choices: d.choices.map { c in
                (c, content.events[d.event]?.choices?.first { $0.id == c }.map { p.text($0.label) } ?? p.text(Perceiver.unknownText))
            }, prompt: content.events[d.event]?.prompt.map { p.text($0) })
        }
    }

    func sceneLines(_ w: WorldState, _ p: Perceiver) -> [String] {
        guard let s = w.narrative.scene, let def = content.scenes[s.scene] else { return [] }
        guard def.style != .prologue, def.style != .stage else { return [] }
        return shownLines(def, s, w).suffix(3).map { p.text($0.text) }
    }

    /// 今の行までの行のうち、条件(Line.when)が成り立たずに飛ばした行(同じ枠の言い換えなど)を除いた物。
    /// 今の行はいつも入れる。ふきだしも全画面の場面も、この物だけを見せる。
    func shownLines(_ def: SceneDef, _ s: SceneProgress, _ w: WorldState) -> [SceneDef.Line] {
        def.lines.prefix(s.line + 1).enumerated().filter { i, line in
            i == s.line || line.when.map {
                ConditionEvaluator.evaluatePure($0, world: w, content: content, trigger: s.origin) == true
            } ?? true
        }.map(\.element)
    }

    func prologue(_ w: WorldState, _ p: Perceiver) -> PrologueView? {
        guard let s = w.narrative.scene, let def = content.scenes[s.scene] else { return nil }
        let kind: PrologueView.Kind
        switch def.style {
        case .some(.prologue): kind = .prologue
        case .some(.stage): kind = .stage
        case .some(.bubble), .none: return nil
        }
        let lines = shownLines(def, s, w)
        return PrologueView(kind: kind, lines: lines.map { p.text($0.text) },
                            speakers: lines.map { $0.speaker.map { p.name(content.people[$0]?.name ?? Subject.person($0)) } },
                            waiting: true)
    }

    func darkStart(_ w: WorldState) -> DarkStartView? {
        guard w.run.isActive, w.clock.held,
              !w.narrative.pending.contains(where: \.blocking),
              prologue(w, Perceiver(content: content, world: w)) == nil,
              let position = w.people[.noah]?.position, position.layer == layer,
              let card = footCard(w, at: position.point)
        else { return nil }
        let action: FootCard.Action?
        if let id = content.start.clock?.firstAct {
            action = card.actions.first { $0.id == id }
        } else {
            action = card.actions.first
        }
        return action.map { DarkStartView(action: $0) }
    }

    // MARK: - 地図の引き出し

    /// 区画の中身(画面が版の変わった区画だけ引く)。
    public func chunks(_ w: WorldState, _ indices: [Int], map: MapView) -> [MapChunk] {
        if prologue(w, Perceiver(content: content, world: w)) != nil {
            return indices.filter { $0 >= 0 && $0 < map.chunkRevisions.count }.map { index in
                let rect = map.chunkRect(index)
                return MapChunk(index: index, revision: map.chunkRevisions[index], rect: rect,
                                tiles: Array(repeating: .void, count: rect.size.count))
            }
        }
        let proj = MapProjector(world: w, content: content, perceiver: Perceiver(content: content, world: w), layer: layer)
        let n = map.chunkColumns * map.chunkRows
        return indices.filter { $0 >= 0 && $0 < n }.map { proj.chunk($0, map: map) }
    }

    /// 1 マスの見え方(視界も含めて)。
    public func tile(_ w: WorldState, at pt: GridPoint) -> TileView {
        let proj = MapProjector(world: w, content: content, perceiver: Perceiver(content: content, world: w), layer: layer)
        var t = proj.tile(pt)
        if proj.size.contains(pt), vision.areas(w, layer: layer).contains(where: { $0.contains(pt) }) {
            t.fog = .visible
            t.shadow = nil
        }
        return t
    }

    /// 長押しで調べる(ふきだし)。未踏のマスは「？」だけ。
    /// 調べたマスの地形と POI の種類(見えていないマスは nil。GameHost.inspect が世界に覚えさせる)。
    public func inspectedKinds(_ w: WorldState, at pt: GridPoint) -> (terrain: TerrainID?, poi: POIKindID?)? {
        let p = Perceiver(content: content, world: w)
        let proj = MapProjector(world: w, content: content, perceiver: p, layer: layer)
        guard let l = proj.layer, proj.size.contains(pt),
              proj.isKnown(pt) || vision.areas(w, layer: layer).contains(where: { $0.contains(pt) }) else { return nil }
        return (l.terrain(at: pt), proj.poiAt[pt]?.poi.kind)
    }

    public func inspect(_ w: WorldState, at pt: GridPoint) -> TileInspection? {
        let p = Perceiver(content: content, world: w)
        let proj = MapProjector(world: w, content: content, perceiver: p, layer: layer)
        guard let l = proj.layer, proj.size.contains(pt) else { return nil }
        let seen = proj.isKnown(pt) || vision.areas(w, layer: layer).contains { $0.contains(pt) }
        guard seen else { return TileInspection(point: pt, title: p.text(Perceiver.unknownText), lines: []) }
        var title = l.terrain(at: pt).map { p.terrainName($0, spent: proj.isSpent(pt, terrain: $0)) } ?? p.text(Perceiver.unknownText)
        var lines: [TileInspection.Line] = []
        if let poi = proj.poiAt[pt] { title = p.name(Subject.poi(poi.poi.kind)) }
        if let d = proj.depositAt[pt] {
            lines.append(.name(p.name(PresentSubject.deposit(d.deposit))))
            lines.append(.remaining(d.deposit.remainingExtractions))
            // ノアの手ざわり: 鉱脈を見つけて(触れて)いれば純度の見当(割)が分かる。
            // TODO(U7/U8): 鉱脈の発見の正を knowledge(巻き戻しで残る)に置いたら、そちらを見る。
            if d.deposit.isDiscovered {
                lines.append(.purityTenths(min(10, max(1, (d.deposit.purity.basisPoints + 500) / 1000))))
            }
        }
        return TileInspection(point: pt, title: title, lines: lines)
    }

    /// 足元カード: 注目しているマスの名前と、いまできる行為(1〜3 個)。
    /// 行為はコンテンツの InteractionDef(対象・昼夜・条件)から引く。距離・回数の上限は探索の担当が断る(理由は足元カードに 1 行)。
    public func footCard(_ w: WorldState, at pt: GridPoint, page: Int = 0) -> FootCard? {
        if prologue(w, Perceiver(content: content, world: w)) != nil {
            return FootCard(point: pt, title: "", actions: [])
        }
        let p = Perceiver(content: content, world: w)
        let proj = MapProjector(world: w, content: content, perceiver: p, layer: layer)
        guard let l = proj.layer, proj.size.contains(pt), let terrain = l.terrain(at: pt) else { return nil }
        let seen = proj.isKnown(pt) || vision.areas(w, layer: layer).contains { $0.contains(pt) }
        guard seen else {
            var card = FootCard(point: pt, title: p.text(Perceiver.unknownText), actions: [])
            card.state = .unseen
            card.hint = p.text("ui.foot.hint.unseen")
            return card
        }
        let poi = proj.poiAt[pt]
        let deposit = proj.depositAt[pt]
        let placed = w.placements.sortedIDs.compactMap { w.placements.items[$0] }.filter { pl in
            pl.at.layer == layer && (pl.at.point == pt || pl.footprint.contains { GridPoint(pl.at.point.x + $0.x, pl.at.point.y + $0.y) == pt })
        }
        var title = p.terrainName(terrain, spent: proj.isSpent(pt, terrain: terrain))
        if let d = deposit { title = p.name(PresentSubject.deposit(d.deposit)) }
        if let poi { title = p.name(Subject.poi(poi.poi.kind)) }
        if let pl = placed.first {
            title = switch pl.kind {
            case .module(let k): p.name(Subject.module(k))
            case .structure(let k): p.name(Subject.structure(k))
            }
        }
        let at = WorldPoint(layer, pt)
        let ui = unlocks(w)
        // 足元カードの行為は、手の届く所(ノアのマスと隣の 8 マス)のものだけ。歩かずにその場でできる物だけを出す(DEC-F2 v0.2)。
        let noahPoint = w.people[.noah]?.position.flatMap { $0.layer == layer ? $0.point : nil }
        let reachable = noahPoint.map { $0.chebyshev(to: pt) <= Reach.tiles } ?? false
        var actions: [FootCard.Action] = []
        if let noahPoint, reachable {
            if pt == noahPoint {
                var neighbours: [GridPoint] = []
                for dy in -Reach.tiles...Reach.tiles {
                    for dx in -Reach.tiles...Reach.tiles where dx != 0 || dy != 0 {
                        let q = GridPoint(pt.x + dx, pt.y + dy)
                        if proj.size.contains(q) { neighbours.append(q) }
                    }
                }
                let own = tileActions(w, p, proj, ui: ui, at: pt)
                let around = neighbours.flatMap { tileActions(w, p, proj, ui: ui, at: $0) }
                    .sorted { ($0.id, $0.target.x, $0.target.y) < ($1.id, $1.target.x, $1.target.y) }
                actions = own + around
            } else {
                actions = tileActions(w, p, proj, ui: ui, at: pt)
            }
        }
        let pageCount = max(1, (actions.count + FootCard.maxActions - 1) / FootCard.maxActions)
        let pageIndex = max(0, min(page, pageCount - 1))
        let slice = Array(actions.dropFirst(pageIndex * FootCard.maxActions).prefix(FootCard.maxActions))
        var card = FootCard(point: pt, title: title, actions: slice)
        card.page = pageIndex
        card.pageCount = pageCount
        let busy = w.exploration.active.values.contains { $0.at == at } || placed.contains {
            if case .underConstruction = $0.status { return true }
            return false
        }
        if busy {
            card.state = .busy
            card.hint = p.text("ui.foot.hint.busy")
        } else if !reachable {
            // 遠いマス: ボタンは出さない(名前と理由の 1 行だけ。歩くのは操作棒)
            card.state = .far
            card.hint = p.text("ui.foot.hint.far")
        } else if card.actions.isEmpty {
            card.state = .empty
            card.hint = p.text("ui.foot.hint.empty")
        }
        card.nothingNearby = w.exploration.continueStop != nil
        card.fire = placed.lazy.compactMap { fireView($0, w) }.first
        if let poi {
            // 残骸から開く資料(段のある資料のうち、この種類の POI に付いていて、いま記録に載るもの)
            card.documents = content.documents.keys.sorted().compactMap { id in
                guard let d = content.documents[id], d.stages?.poiKind == poi.poi.kind,
                      ConditionEvaluator.evaluatePure(d.when, world: w, content: content) == true else { return nil }
                return FootCard.DocumentLink(id: id, title: p.text(d.title))
            }
        }
        return card
    }

    /// 1 マスにあるいまできる行為(対象・昼夜・条件で絞る。ID の順)。届くかは呼ぶ側が決める。
    func tileActions(_ w: WorldState, _ p: Perceiver, _ proj: MapProjector, ui: UIUnlocks, at pt: GridPoint) -> [FootCard.Action] {
        guard let l = proj.layer, proj.size.contains(pt), let terrain = l.terrain(at: pt),
              proj.isKnown(pt) || vision.areas(w, layer: layer).contains(where: { $0.contains(pt) }) else { return [] }
        let poi = proj.poiAt[pt]
        let deposit = proj.depositAt[pt]
        let placed = w.placements.sortedIDs.compactMap { w.placements.items[$0] }.filter { pl in
            pl.at.layer == layer && (pl.at.point == pt || pl.footprint.contains { GridPoint(pl.at.point.x + $0.x, pl.at.point.y + $0.y) == pt })
        }
        let tags = Set(content.terrains[terrain]?.tags ?? [])
        let at = WorldPoint(layer, pt)
        return content.interactions.keys.sorted().compactMap { id -> FootCard.Action? in
            guard let def = content.interactions[id] else { return nil }
            let applies: Bool = switch def.target {
            case .terrain(let tag): tags.contains(tag)
            case .poi(let kind): poi?.poi.kind == kind
            case .deposit: deposit.map { $0.deposit.remainingExtractions > 0 } ?? false
            case .structure(let kind): placed.contains { $0.kind == .structure(kind) }
            case .module(let kind): placed.contains { $0.kind == .module(kind) }
            }
            guard applies, ui.isOpen(.interaction(id)),
                  Interactions.isUnlocked(id, world: w, gated: content.gatedUnlocks) else { return nil }
            if let phases = def.allowedPhases, !phases.contains(w.clock.phase) { return nil }
            if let c = def.when, ConditionEvaluator.evaluatePure(c, world: w, content: content) == false { return nil }
            // クールダウン中のマスは押しても断られるので、ボタンを出さない(地図の使い切りの見た目と同じ判定)
            if case .terrain = def.target, Interactions.isCoolingDown(def, at: at, world: w) { return nil }
            return FootCard.Action(id: id, label: p.name(PresentSubject.interaction(id)),
                                   hold: def.hold || def.continues == true, at: at,
                                   progressPermille: progress(of: def, w))
        }
    }

    /// ノアのいまの 1 単位の進み(千分率)。この行為を押している間だけ。
    func progress(of def: InteractionDef, _ w: WorldState) -> Int? {
        guard let a = w.exploration.active[.noah], a.interaction == def.id, def.seconds > 0 else { return nil }
        if (def.hold || def.continues == true) && !a.holding { return nil }
        return Int(max(0, min(1000, a.progress * 1000 / Int64(def.seconds))))
    }

    /// 焚き火(火床のある建造物)の足元カードの火の見込み。くべる行為(効果 hearth addFuel)の品で 1 本くべた後を出す。
    /// くべる行為が無ければ、定義の燃料のうち ID が最初の品を使う。
    func fireView(_ pl: Placement, _ w: WorldState) -> FireOutlookView? {
        guard case .structure = pl.kind, let d = Hearths.def(pl, content), let s = Hearths.state(pl, content),
              Hearths.isCompleteForOutlook(pl) else { return nil }
        let n = Hearths.structuresInLight(pl.id, in: w, content: content)
        let modifiers = Hearths.modifiers(pl.id, in: w, content: content)
        let item: ItemID? = content.interactions.keys.sorted().compactMap { id -> ItemID? in
            for e in content.interactions[id]?.effects ?? [] {
                if case .hearth(_, .addFuel(let item, _)) = e { return item }
            }
            return nil
        }.first ?? d.fuels.keys.sorted().first
        let now = HearthRule.outlook(s, d, now: w.clock.now, clock: content.clock, structuresInLight: n,
                                     modifiers: modifiers)
        let after = item.map {
            HearthRule.outlookAfterOneMore(s, d, item: $0, now: w.clock.now, clock: content.clock,
                                            structuresInLight: n, modifiers: modifiers)
        } ?? now
        return FireOutlookView(now: now, afterOneMore: after)
    }

    /// 日没の帯の火の見込み(番が火を見ていれば薪の置き場の本数も入れた 4 段)。拠点の焚き火のうち ID が最初のもの。
    func duskFireOutlook(_ w: WorldState) -> FireOutlook? {
        guard w.clock.phase != .day else { return nil }
        for id in Hearths.structureHearths(w, content) {
            guard let pl = w.placements.items[id], Hearths.isCompleteForOutlook(pl), let d = Hearths.def(pl, content),
                  let s = Hearths.state(pl, content) else { continue }
            let n = Hearths.structuresInLight(id, in: w, content: content)
            let modifiers = Hearths.modifiers(id, in: w, content: content)
            return HearthRule.outlookWithPile(s, d, now: w.clock.now, clock: content.clock, structuresInLight: n,
                                              tended: Hearths.isTended(id, in: w), modifiers: modifiers)
        }
        return nil
    }

    // MARK: - 工程表

    /// 工程表(ライン札・試作・コンテンツの記録)を同じ形にする。
    public func sheet(_ source: ProcessSheet.Source, in w: WorldState) -> ProcessSheet? {
        let p = Perceiver(content: content, world: w)
        switch source {
        case .design(let id):
            guard let m = Sheets.model(.design(id), world: w, content: content) else { return nil }
            var out = inventionSheet(m, source: source, p)
            // 試していない札でも、札に書いた見込みがあれば結果に出す
            if out.result == nil, let e = w.invention.designs[id]?.expected {
                out.result = p.name(of: NameGenerator.name(for: e))
            }
            return out
        case .trial(let rec):
            guard let m = Sheets.model(.trial(rec), world: w, content: content) else { return nil }
            return inventionSheet(m, source: source, p)
        case .draft(let steps, let sel):
            let input: Matter? = sel.flatMap { if case .matter(let m) = $0.stuff { m } else { nil } }
            guard let m = Sheets.model(.draft(steps: steps, input: input), world: w, content: content) else { return nil }
            return inventionSheet(m, source: source, p)
        case .record(let sid):
            guard let def = content.sheets[sid],
                  ConditionEvaluator.evaluatePure(def.when, world: w, content: content) == true else { return nil }
            let prog = w.narrative.sheet(sid)
            var out = recordRows(def.rows, p, w, prog)
            var tally: ProcessSheet.Tally?
            if let n = def.slots {
                // 記録の並び: 席の順に、記録のある席と空いた席が同じ形で並ぶ
                let entries = Dictionary(uniqueKeysWithValues: SheetRules.entries(def, w, content).map { ($0.slot, $0) })
                for slot in 1...max(n, 1) {
                    if let e = entries[slot] {
                        out.append(ProcessSheet.Row(title: p.name(e.subject), note: nil, slot: slot, person: e.person))
                    } else {
                        out.append(ProcessSheet.Row(title: p.text("text.sheet.slot_empty"), note: nil, slot: slot, empty: true))
                    }
                }
                tally = ProcessSheet.Tally(filled: entries.count, slots: n)
            }
            if let m = def.roster, m.when.map({ ConditionEvaluator.evaluatePure($0, world: w, content: content) == true }) ?? true {
                for person in SheetRules.candidates(w) {
                    out.append(ProcessSheet.Row(title: p.name(Subject.person(person)), note: nil,
                                                included: prog.chosen[person] ?? prog.declared[person],
                                                declared: prog.declared[person], person: person))
                }
            }
            var sheet = ProcessSheet(source: source, title: p.name(def.title), rows: out, result: nil, tally: tally)
            func label(_ id: TextID, _ fallback: String) -> String { content.texts[id] ?? fallback }
            sheet.labels = .init(
                rosterInclude: label("ui.roster.include", "含める"),
                rosterExclude: label("ui.roster.exclude", "含めない"),
                rosterConfirm: label("ui.roster.confirm", "確定する"),
                rosterConfirmHint: label("ui.roster.confirm_hint", "長押しで確定"),
                grantTitle: label("ui.grant.title", "技能を付ける"),
                grantSkip: label("ui.grant.skip", "付けない"),
                grantRefused: label("ui.grant.refused", "本人が断った")
            )
            if let im = def.grant, SheetRules.grantOpen(im, w, content) {
                sheet.grant = ProcessSheet.SkillGrant(
                    skills: im.skills.map { .init(id: $0, name: p.name(Subject.skill($0))) },
                    targets: SheetRules.candidates(w).filter { SheetRules.grantTarget(im, $0, w, content) }.map { person in
                        .init(person: person, name: p.name(Subject.person(person)),
                              written: (prog.granted[person] ?? []).map { p.name(Subject.skill($0)) },
                              declined: prog.declined[person])
                    })
            }
            if def.roster != nil { sheet.rosterConfirmed = prog.locked != nil }
            return sheet
        case .recordEntry(let sid, let slot):
            guard let def = content.sheets[sid],
                  ConditionEvaluator.evaluatePure(def.when, world: w, content: content) == true else { return nil }
            let prog = w.narrative.sheet(sid)
            if let e = SheetRules.entries(def, w, content).first(where: { $0.slot == slot }) {
                return ProcessSheet(source: source, title: p.name(def.title),
                                    rows: recordRows(e.rows ?? def.entryRows ?? [], p, w, prog),
                                    result: p.name(e.subject))
            }
            // 空いた席: 行も結果も無い(それ自体が見えるもの)
            guard SheetRules.emptySlots(def, w, content).contains(slot) else { return nil }
            return ProcessSheet(source: source, title: p.name(def.title), rows: [], result: nil)
        }
    }

    private func recordRows(_ rows: [SheetDef.Row], _ p: Perceiver, _ w: WorldState, _ prog: SheetProgress) -> [ProcessSheet.Row] {
        rows.compactMap { r in
            if let c = r.when, ConditionEvaluator.evaluatePure(c, world: w, content: content) != true { return nil }
            var row = ProcessSheet.Row(title: p.name(r.subject), note: r.note.map { p.text($0) })
            row.figure = r.measure.map { SheetRules.measure($0, w) }
            if r.answer != nil, let id = r.id {
                row.answerRow = id
                row.answer = prog.answers[id].flatMap { w.ledger.record($0) }.flatMap { p.journalLine($0) }
            }
            return row
        }
    }

    /// 行に置ける答えの候補(自分の来歴から。新しい順)。
    public func answerCandidates(_ sid: SheetID, row: String, in w: WorldState) -> [AnswerCandidate] {
        guard let r = content.sheets[sid]?.rows.first(where: { $0.id == row }) else { return [] }
        let p = Perceiver(content: content, world: w)
        return SheetRules.answerCandidates(r, w).compactMap { rec in
            p.journalLine(rec).map { AnswerCandidate(record: rec.id, label: $0) }
        }
    }
}
