import RFContent
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
        frame.benchRevision = Self.benchRevision(previous: previous, report: report, revision: revision, day: w.clock.day)
        return frame
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
        return ClockView(
            day: w.clock.day, phase: w.clock.phase,
            dayRemainingPermille: w.clock.phase == .day && dayLen > 0 ? Int(max(0, (dayLen - since) * 1000 / dayLen)) : 0,
            running: w.run.isActive && w.clock.phase == .day && !w.narrative.pending.contains(where: \.blocking))
    }

    func statusItems(_ w: WorldState, _ p: Perceiver) -> [StatusItem] {
        // 赤の判定は生存の担当が StatDef に足す(alertBelow など)。入ったらここで写す。
        w.survival.stats.keys.sorted().compactMap { id in
            p.stat(id, value: w.survival.stats[id] ?? .zero).map {
                StatusItem(key: id.rawValue, label: p.name(Subject.stat(id)), value: $0, alert: false)
            }
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
            return ActorSprite(id: id.rawValue, glyph: isNoah ? ActorSprite.arrow(ps.facing) : p.glyph(Subject.person(id)),
                               from: pos.point, to: next, progress: ps.motion?.progress ?? 0, facing: ps.facing,
                               label: p.name(Subject.person(id)), isNoah: isNoah, isMember: member,
                               tint: isNoah ? TilePalette.noah : (member ? TilePalette.member : TilePalette.stranger))
        }
    }

    /// 置いた物は、既知か視界の中のマスにあるものだけ。
    func placements(_ w: WorldState, _ p: Perceiver, proj: MapProjector, map: MapView) -> [PlacementSprite] {
        w.placements.sortedIDs.compactMap { id in
            guard let pl = w.placements.items[id], pl.at.layer == layer,
                  proj.isKnown(pl.at.point) || map.isVisible(pl.at.point) else { return nil }
            let s: SubjectID = switch pl.kind {
            case .module(let k): Subject.module(k)
            case .structure(let k): Subject.structure(k)
            }
            var reason: String?
            if case .stopped(let r) = pl.status { reason = p.text(r) }
            return PlacementSprite(id: id, glyph: p.glyph(s), at: pl.at.point, facing: pl.facing,
                                   running: pl.status == .running, stoppedReason: reason, throughput: nil)
        }
    }

    func decision(_ w: WorldState, _ p: Perceiver) -> DecisionView? {
        w.narrative.pending.first.map { d in
            DecisionView(id: d.id, blocking: d.blocking, choices: d.choices.map { c in
                (c, content.events[d.event]?.choices?.first { $0.id == c }.map { p.text($0.label) } ?? p.text(Perceiver.unknownText))
            })
        }
    }

    func sceneLines(_ w: WorldState, _ p: Perceiver) -> [String] {
        guard let s = w.narrative.scene, let def = content.scenes[s.scene] else { return [] }
        return def.lines.prefix(s.line + 1).suffix(3).map { p.text($0.text) }
    }

    // MARK: - 地図の引き出し

    /// 区画の中身(画面が版の変わった区画だけ引く)。
    public func chunks(_ w: WorldState, _ indices: [Int], map: MapView) -> [MapChunk] {
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
    public func inspect(_ w: WorldState, at pt: GridPoint) -> TileInspection? {
        let p = Perceiver(content: content, world: w)
        let proj = MapProjector(world: w, content: content, perceiver: p, layer: layer)
        guard let l = proj.layer, proj.size.contains(pt) else { return nil }
        let seen = proj.isKnown(pt) || vision.areas(w, layer: layer).contains { $0.contains(pt) }
        guard seen else { return TileInspection(point: pt, title: p.text(Perceiver.unknownText), lines: []) }
        var title = l.terrain(at: pt).map { p.name(Subject.terrain($0)) } ?? p.text(Perceiver.unknownText)
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
    public func footCard(_ w: WorldState, at pt: GridPoint) -> FootCard? {
        let p = Perceiver(content: content, world: w)
        let proj = MapProjector(world: w, content: content, perceiver: p, layer: layer)
        guard let l = proj.layer, proj.size.contains(pt), let terrain = l.terrain(at: pt) else { return nil }
        let seen = proj.isKnown(pt) || vision.areas(w, layer: layer).contains { $0.contains(pt) }
        guard seen else { return FootCard(point: pt, title: p.text(Perceiver.unknownText), actions: []) }
        let poi = proj.poiAt[pt]
        let deposit = proj.depositAt[pt]
        let placed = w.placements.sortedIDs.compactMap { w.placements.items[$0] }.filter { pl in
            pl.at.layer == layer && (pl.at.point == pt || pl.footprint.contains { GridPoint(pl.at.point.x + $0.x, pl.at.point.y + $0.y) == pt })
        }
        let tags = Set(content.terrains[terrain]?.tags ?? [])
        var title = p.name(Subject.terrain(terrain))
        if let d = deposit { title = p.name(PresentSubject.deposit(d.deposit)) }
        if let poi { title = p.name(Subject.poi(poi.poi.kind)) }
        if let pl = placed.first {
            title = switch pl.kind {
            case .module(let k): p.name(Subject.module(k))
            case .structure(let k): p.name(Subject.structure(k))
            }
        }
        let at = WorldPoint(layer, pt)
        let actions = content.interactions.keys.sorted().compactMap { id -> FootCard.Action? in
            guard let def = content.interactions[id] else { return nil }
            let applies: Bool = switch def.target {
            case .terrain(let tag): tags.contains(tag)
            case .poi(let kind): poi?.poi.kind == kind
            case .deposit: deposit.map { $0.deposit.remainingExtractions > 0 } ?? false
            case .structure(let kind): placed.contains { $0.kind == .structure(kind) }
            case .module(let kind): placed.contains { $0.kind == .module(kind) }
            }
            guard applies else { return nil }
            if let phases = def.allowedPhases, !phases.contains(w.clock.phase) { return nil }
            if let c = def.when, ConditionEvaluator.evaluatePure(c, world: w, content: content) == false { return nil }
            return FootCard.Action(id: id, label: p.name(PresentSubject.interaction(id)), hold: def.hold, at: at)
        }
        return FootCard(point: pt, title: title, actions: Array(actions.prefix(FootCard.maxActions)))
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
            if let m = def.manifest, m.when.map({ ConditionEvaluator.evaluatePure($0, world: w, content: content) == true }) ?? true {
                for person in SheetRules.candidates(w) {
                    out.append(ProcessSheet.Row(title: p.name(Subject.person(person)), note: nil,
                                                aboard: prog.chosen[person] ?? prog.declared[person],
                                                declared: prog.declared[person], person: person))
                }
            }
            var sheet = ProcessSheet(source: source, title: p.name(def.title), rows: out, result: nil, tally: tally)
            if let im = def.imprint, SheetRules.imprintOpen(im, w, content) {
                sheet.imprint = ProcessSheet.Imprint(
                    skills: im.skills.map { .init(id: $0, name: p.name(Subject.skill($0))) },
                    targets: SheetRules.candidates(w).filter { SheetRules.imprintTarget(im, $0, w, content) }.map { person in
                        .init(person: person, name: p.name(Subject.person(person)),
                              written: (prog.imprinted[person] ?? []).map { p.name(Subject.skill($0)) },
                              declined: prog.declined[person])
                    })
            }
            if def.manifest != nil { sheet.manifestLocked = prog.locked != nil }
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
