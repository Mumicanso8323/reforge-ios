import RFContent
import RFKernel
import RFMap
import RFMatter
import RFPerception
import RFRules
import RFSim
import RFWorld

/// 世界状態 → Frame(と、区画・工程表などの引き出し)。持ち主: UI の担当(UI-a)。
/// 骨組みとして最小の項目だけを埋めてある。
public struct FrameBuilder: Sendable {
    public let content: ContentDB

    public init(content: ContentDB) { self.content = content }

    public func build(_ w: WorldState, revision: Int, previous: Frame?, report: StepReport?) -> Frame {
        let p = Perceiver(content: content, world: w)
        let layer = LayerID.surface
        let size = w.map[layer]?.size ?? GridSize(width: 0, height: 0)
        let cs = MapView.chunkSize
        let chunks = ((size.width + cs - 1) / cs) * ((size.height + cs - 1) / cs)
        var revs = previous?.map.chunkRevisions ?? Array(repeating: 0, count: chunks)
        if revs.count != chunks { revs = Array(repeating: revision, count: chunks) }
        if let r = report {
            if r.changes.areas.contains(.perception) {
                revs = revs.map { _ in revision }
            } else {
                for t in r.changes.dirtyTiles where t.layer == layer && size.contains(t.point) {
                    revs[(t.point.y / cs) * ((size.width + cs - 1) / cs) + t.point.x / cs] = revision
                }
            }
        }
        let actors = w.people.members.compactMap { id -> ActorSprite? in
            guard let ps = w.people[id], let pos = ps.position, pos.layer == layer else { return nil }
            let next = ps.motion?.path.first ?? pos.point
            return ActorSprite(id: id.rawValue, glyph: p.glyph(Subject.person(id)), from: pos.point, to: next,
                               progress: ps.motion?.progress ?? 0, facing: ps.facing, label: p.name(Subject.person(id)))
        }
        let decision = w.narrative.pending.first.map { d in
            DecisionView(id: d.id, blocking: d.blocking, choices: d.choices.map { c in
                (c, content.events[d.event]?.choices?.first { $0.id == c }.map { p.text($0.label) } ?? p.text(Perceiver.unknownText))
            })
        }
        var sceneLines: [String] = []
        if let s = w.narrative.scene, let def = content.scenes[s.scene] {
            sceneLines = def.lines.prefix(s.line + 1).suffix(3).map { p.text($0.text) }
        }
        let dayLen = content.clock.dayGameSeconds
        let since = (w.clock.now - w.clock.dayStartedAt).seconds
        return Frame(
            revision: revision,
            clock: ClockView(day: w.clock.day, phase: w.clock.phase,
                             dayRemainingPermille: w.clock.phase == .day && dayLen > 0 ? Int(max(0, (dayLen - since) * 1000 / dayLen)) : 0,
                             running: w.run.isActive && w.clock.phase == .day && !w.narrative.pending.contains(where: \.blocking)),
            status: w.survival.stats.keys.sorted().compactMap { id in
                p.stat(id, value: w.survival.stats[id] ?? .zero).map {
                    StatusItem(key: id.rawValue, label: p.name(Subject.stat(id)), value: $0, alert: false)
                }
            },
            map: MapView(layer: layer, size: size, chunkRevisions: revs),
            actors: actors,
            placements: w.placements.sortedIDs.compactMap { id in
                guard let pl = w.placements.items[id], pl.at.layer == layer else { return nil }
                let s: SubjectID = switch pl.kind {
                case .module(let k): Subject.module(k)
                case .structure(let k): Subject.structure(k)
                }
                var reason: String?
                if case .stopped(let r) = pl.status { reason = p.text(r) }
                return PlacementSprite(id: id, glyph: p.glyph(s), at: pl.at.point, facing: pl.facing,
                                       running: pl.status == .running, stoppedReason: reason, throughput: nil)
            },
            decision: decision,
            sceneLines: sceneLines,
            notices: [],
            renamed: [])
    }

    /// 1 マスの見え方(区画を描くときに画面が呼ぶ)。
    public func tile(_ w: WorldState, _ p: Perceiver, layer: LayerID, at pt: GridPoint) -> TileView {
        guard let l = w.map[layer], let t = l.terrain(at: pt) else { return TileView(glyph: " ", tint: "void", fog: .unknown) }
        let known = w.knowledge.mapKnown[layer]?[pt] ?? false
        return TileView(glyph: known ? p.glyph(Subject.terrain(t)) : " ", tint: t.rawValue,
                        fog: known ? .remembered : .unknown)
    }

    /// 工程表(ライン札・試作・コンテンツの記録)を同じ形にする。
    public func sheet(_ source: ProcessSheet.Source, in w: WorldState) -> ProcessSheet? {
        let p = Perceiver(content: content, world: w)
        func rows(_ steps: [ProcessStep]) -> [ProcessSheet.Row] {
            steps.map { s in
                ProcessSheet.Row(title: p.name(Subject.module(s.module)), note: s.input.map { p.name(Subject.item($0)) })
            }
        }
        switch source {
        case .design(let id):
            guard let d = w.invention.designs[id] else { return nil }
            return ProcessSheet(source: source, title: p.text("text.sheet.design"), rows: rows(d.steps),
                                result: d.expected.map { p.name(of: NameGenerator.name(for: $0)) })
        case .trial(let rec):
            guard let t = w.notebook.trials.first(where: { $0.record == rec }) else { return nil }
            return ProcessSheet(source: source, title: p.text("text.sheet.trial"), rows: rows(t.steps),
                                result: p.name(of: t.outcome.name))
        case .record(let sid):
            guard let def = content.sheets[sid],
                  ConditionEvaluator.evaluatePure(def.when, world: w, content: content) == true else { return nil }
            return ProcessSheet(source: source, title: p.name(def.title), rows: def.rows.compactMap { r in
                if let c = r.when, ConditionEvaluator.evaluatePure(c, world: w, content: content) != true { return nil }
                return ProcessSheet.Row(title: p.name(r.subject), note: r.note.map { p.text($0) })
            }, result: nil)
        }
    }
}
