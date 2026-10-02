import RFContent
import RFKernel
import RFWorld

/// 人の規則の数(出典つき)。R1 の仮値はそう書く。
public enum CrewRules {
    /// 歩く速さ: 昼の実時間 1 秒に 4 マス(原作 MapScreen.cs:71 MoveAnimInterval 0.25 秒)。
    /// ゲーム時間に直して持つので、夜の一括でも同じ速さ(1 マス = 昼の実時間 0.25 秒ぶんのゲーム秒)。
    public static let tilesPerRealSecond = 4

    /// 1 ステップで次のマスへ進む量(千分率)。既定の時計(昼 180 実秒 = 8 時間)で 375。
    public static func progressPerStep(_ clock: ClockDef) -> Int {
        let num = Int64(tilesPerRealSecond) * SimStep.gameSeconds * 1000 * Int64(clock.dayRealSeconds)
        return max(1, Int(num / max(1, clock.dayGameSeconds)))
    }

    /// 範囲の効果で配属を上書きされたノア(プレイヤーが動かす人)の足取り(千分率)。止めない(BEAT-22。R1 の仮値)。
    public static let heavyStepPermille = 333

    // MARK: 配属の効き(order.md §5.6。原作 PlacedModule.GetWorkerBonus)

    /// 専門一致 +30%。
    public static let specialtyBonusPermille = 300
    /// 関係ランク 3 以上 +10%。
    public static let rankBonusPermille = 100
    public static let rankBonusAt = 3
    /// 思想と配属の向き(配属の印 × 思想の重み)1 点あたりの速さ(R1 の仮値)と上限。
    public static let ideologySpeedPerPoint = 20
    public static let ideologySpeedCap = 200

    // MARK: 関係(R1 の仮値。原作には関係の点の入り口が無い)

    /// 賛否 1 回で動く点の上限(賛否の強さ = Σ 思想の値 × 印の重み をこの幅に収める)。
    public static let opinionPointCap = 20
    /// 焚き火で話す: 1 晩に 1 回、関係の点 +30。10 晩ほど毎晩話せばランク 3 に届く(シリカのヒント、order.md §5.4)。
    public static let talkPoints = 30
    /// 話すのにかかる時間(夜作業)。
    public static let talkDuration = GameDuration.hours(1)

    // MARK: 動き

    /// ついて行く人がこれより離れたら追う(マス)。
    public static let followDistance = 2
    /// 運搬の端で積み下ろしに待つ時間。
    public static let haulDwell = GameDuration(seconds: 30)
    /// 行き先に届かなかったとき、次に経路を探すまで待つ時間。
    public static let retryDelay = GameDuration.hours(1)
}

/// 配属の印(来歴の印と同じ型)。思想の軸の重み(IdeologyAxisDef.weights)がこれを見て、
/// 配属の速さと、配属という判断への賛否を決める。コンテンツは "tag.assign.operate.furnace" などに重みを書く。
public enum AssignmentTags {
    public static func tags(for a: Assignment, in w: WorldState) -> Set<ProvenanceTag> {
        switch a {
        case .idle: return []
        case .rest: return ["tag.assign.rest"]
        case .haul: return ["tag.assign.haul"]
        case .guardArea: return ["tag.assign.guard"]
        case .follow: return ["tag.assign.follow"]
        case .tendHearth: return ["tag.assign.tend"]
        case .gather(let i, _): return ["tag.assign.gather", ProvenanceTag("tag.assign.gather.\(i.rawValue)")]
        case .operate(let e): return Set<ProvenanceTag>(["tag.assign.operate"]).union(kindTag("tag.assign.operate", e, w))
        case .build(let e): return Set<ProvenanceTag>(["tag.assign.build"]).union(kindTag("tag.assign.build", e, w))
        }
    }

    private static func kindTag(_ prefix: String, _ e: EntityID, _ w: WorldState) -> Set<ProvenanceTag> {
        guard let p = w.placements.items[e] else { return [] }
        switch p.kind {
        case .module(let k): return [ProvenanceTag("\(prefix).\(k.rawValue)")]
        case .structure(let k): return [ProvenanceTag("\(prefix).\(k.rawValue)")]
        }
    }

    /// 配属の種類の短い名前(来歴の detail 用。文章ではない)。
    public static func kindName(_ a: Assignment) -> String {
        switch a {
        case .idle: "idle"
        case .rest: "rest"
        case .haul: "haul"
        case .guardArea: "guard"
        case .follow: "follow"
        case .tendHearth: "tend"
        case .gather: "gather"
        case .operate: "operate"
        case .build: "build"
        }
    }
}

/// 思想の傾き × 来歴の印 → 賛否の強さ。
public enum Ideology {
    /// Σ_軸 (その人の軸の値 × Σ_印 軸の重み[印])。正は賛成、負は反対。
    public static func stance(_ ideology: [IdeologyAxisID: Int], tags: Set<ProvenanceTag>, content: ContentDB) -> Int {
        guard !tags.isEmpty else { return 0 }
        var total = 0
        for (axis, v) in ideology.sorted(by: { $0.key < $1.key }) where v != 0 {
            guard let def = content.ideologyAxes[axis] else { continue }
            for t in tags { total += v * (def.weights[t] ?? 0) }
        }
        return total
    }
}
