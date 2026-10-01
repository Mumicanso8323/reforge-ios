import RFContent
import RFKernel
import RFMatter
import RFRules
import RFWorld

/// 画面(RFPresent)とボットが読む生産の見え方。世界を変えない。文字は持たない(ID と数だけ)。
public enum ProductionQueries {
    /// モジュール 1 つの様子(ふきだし・ボトルネックの表示)。
    public struct ModuleReport: Equatable, Sendable {
        public var id: EntityID
        public var kind: ModuleKindID
        public var running: Bool
        /// 止まっている理由(文字列表のキー)と、来ていない物。
        public var stoppedReason: TextID?
        public var waitingFor: ItemID?
        /// 1 日あたりの入/出(昨日の実績。初日は今日の分)。
        public var inPerDay: Int
        public var outPerDay: Int
        /// 止まらずに動けたときの 1 日の出(速さ・1 回の数・処理の時間から)。
        public var capacityPerDay: Int
        /// いまの速さ(千分率)。
        public var speedPermille: Int
        public var operatorID: PersonID?
        /// 使っている有限の品の残り(千分率)。
        public var finiteLeft: Int?
    }

    public static func module(_ id: EntityID, world w: WorldState, content: ContentDB) -> ModuleReport? {
        guard let p = w.placements.items[id], let m = p.module, let kind = p.moduleKind,
              content.modules[kind] != nil else { return nil }
        let tally = m.yesterday.runningSeconds + m.yesterday.idleSeconds > 0 ? m.yesterday : m.today
        var reason: TextID?
        if case .stopped(let r) = p.status { reason = r }
        return ModuleReport(
            id: id, kind: kind, running: p.status == .running, stoppedReason: reason, waitingFor: m.waitingFor,
            inPerDay: tally.received, outPerDay: tally.produced,
            capacityPerDay: capacityPerDay(id, w, content), speedPermille: Modules.speed(id, w, content),
            operatorID: m.operatorID, finiteLeft: m.finite.map { Int(($0.durability ?? ProductionRules.finiteFull).raw) })
    }

    /// 止まらずに動けたときの 1 日の出(採掘口は 1 回 2 個として数える)。
    public static func capacityPerDay(_ id: EntityID, _ w: WorldState, _ content: ContentDB) -> Int {
        guard let p = w.placements.items[id], let m = p.module, let kind = p.moduleKind,
              let def = content.modules[kind] else { return 0 }
        let day = content.clock.dayGameSeconds + content.clock.nightGameSeconds
        let perCycle: Int
        switch Modules.kind(of: m, def) {
        case .extract: perCycle = 2 * m.batch
        case .produce: perCycle = (def.produces ?? []).reduce(0) { $0 + ($1.min + $1.max) / 2 } * m.batch
        case .process: perCycle = m.batch
        case .idle: perCycle = 0
        }
        let s = Int64(Modules.speed(id, w, content))
        return Int(Int64(perCycle) * day * s / (Int64(max(1, def.cycleSeconds)) * 1000))
    }

    /// 札から置いたモジュールの様子(段の順)と、いちばん流れの細い段(ボトルネック)。
    public static func line(_ design: EntityID, world w: WorldState, content: ContentDB)
        -> (modules: [ModuleReport], bottleneck: EntityID?)
    {
        let ids = w.placements.moduleIDs.filter { w.placements.items[$0]?.module?.design == design }
            .sorted { (w.placements.items[$0]?.module?.stepIndex ?? 0, $0) < (w.placements.items[$1]?.module?.stepIndex ?? 0, $1) }
        let reports = ids.compactMap { module($0, world: w, content: content) }
        let neck = reports.min { ($0.capacityPerDay, $0.id) < ($1.capacityPerDay, $1.id) }?.id
        return (reports, neck)
    }

    /// 手作業が「要る」か「任意」か(その資源の T1 が動いているなら任意。足元カードの表示)。
    public enum HandworkStatus: Equatable, Sendable {
        case required
        /// どの T1 が動いているか、その 1 日の出。
        case optional(module: EntityID, perDay: Int)
    }

    public static func handwork(_ id: HandworkID, world w: WorldState, content: ContentDB) -> HandworkStatus {
        guard let kinds = content.handwork[id]?.promotedBy, !kinds.isEmpty else { return .required }
        for pid in w.placements.moduleIDs {
            guard let p = w.placements.items[pid], let k = p.moduleKind, kinds.contains(k), p.status == .running,
                  let r = module(pid, world: w, content: content) else { continue }
            return .optional(module: pid, perDay: r.outPerDay > 0 ? r.outPerDay : r.capacityPerDay)
        }
        return .required
    }

    /// 押し続けている手作業の進み(千分率。バーの表示)。
    public static func handworkProgress(_ p: PersonID = .noah, world w: WorldState, content: ContentDB) -> Int? {
        guard let s = w.placements.handwork[p], let def = content.handwork[s.id] else { return nil }
        let need = Int64(def.presses) * Handwork.pressSeconds(def) * 1000
        return Int(min(1000, s.progress * 1000 / max(1, need)))
    }

    /// 札の i 段目を置ける場所か(照準の影の緑/赤)。
    public static func canPlace(design: EntityID, stepIndex: Int, at: WorldPoint, facing: Direction,
                                world w: WorldState, content: ContentDB) -> Rejection? {
        PlacementCheck.check(design: design, stepIndex: stepIndex, at: at, facing: facing, world: w, content: content)
    }
}
