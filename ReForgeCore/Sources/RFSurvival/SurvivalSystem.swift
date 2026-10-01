import RFContent
import RFKernel
import RFRules
import RFWorld

/// 生存の圧(CORE-07)。食料・水の消費、空腹・渇き、生水の中毒、精神力(外で減り、シェルターで戻る)、体の状態と回復、
/// 拠点全体の数値(内訳と合計・暦などの見せない値)、範囲の効果の bodyPerHour / statPerHour。
///
/// - どれも固定ステップの中で、秒 × 率を整数の端数つきで足す。だから昼をリアルタイムで過ごしても、寝るで一括にしても、
///   刻みの大きさによらず同じ結果になる(1 人 1 日 食料 1・水 1)。
/// - 体の規則は全員に共通(REQ-S5)。人ごとに違うのは、その人がいる場所としていること(外か中か・学んでいるか)だけ。
/// - 餓死・脱水・期限は日数で判定しない。値(survival.stats)を書き、失敗の規則(FailureRuleDef)がその値を見る。
/// - 作業の速さ(空腹 −50% など)は survival.work に書き、他のシステムが SurvivalState.workPermille(for:) で読む。
///
/// 書いてよい切れ端: survival・人の body。乱数の流れ: .survival。受けるコマンド: .survival。
public struct SurvivalSystem: SimSystem {
    public let name = "survival"
    /// テストや道具から規則を差し替えるとき(nil ならコンテンツの規則)。
    public let rulesOverride: SurvivalDef?

    public init(rules: SurvivalDef? = nil) {
        rulesOverride = rules
    }

    /// 使う規則。nil なら食料・水・体の規則は動かない(拠点全体の数値だけ進む)。
    public func rules(_ content: ContentDB) -> SurvivalDef? {
        rulesOverride ?? content.survival
    }

    // MARK: - コマンド

    public func handle(_ command: Command, _ ctx: inout StepContext) -> CommandResult {
        guard case .survival(let c) = command else { return .notMine }
        guard let r = rules(ctx.content) else { return .rejected(Rejection("reason.survival.no_rules")) }
        switch c {
        case .consume(let person, let stock):
            return Body.consume(person: person, stock: stock, r, &ctx)
        case .afflict(let person, let ailment, let severity):
            guard ctx.world.people[person]?.presence.isAlive == true else {
                return .rejected(Rejection("reason.survival.no_person"))
            }
            Body.afflict(person, ailment, severity, r, &ctx)
            return .done
        case .injure(let person, let amount):
            guard ctx.world.people[person]?.presence.isAlive == true else {
                return .rejected(Rejection("reason.survival.no_person"))
            }
            ctx.record(.wasInjured, .person(person), actor: person, place: ctx.world.people[person]?.position,
                       detail: ["amount": .int(Int64(amount))])
            Body.adjust(person, "health", -Int64(amount) * 1000, &ctx)
            Body.afflict(person, r.wound, amount, r, &ctx)
            return .done
        }
    }

    // MARK: - ステップ

    public func step(_ ctx: inout StepContext) {
        Stats.step(&ctx)
        if let r = rules(ctx.content) { Body.step(r, &ctx) }
        Stats.markCrossings(&ctx)
    }

    // MARK: - 出来事

    public func react(to event: DomainEvent, _ ctx: inout StepContext) {
        guard let r = rules(ctx.content) else { return }
        switch event {
        case .walked(let person, _, let cost):
            // 歩いた分だけスタミナが減る(全員に共通)。RFCrew が 1 ステップに 1 回、マスに入った人ごとに出す。
            // staminaCost = 入ったマスの地形の移動コストの合計(草地 10・森 20・岩 30、斜めは 1.4 倍)
            guard cost > 0, ctx.world.people[person]?.presence.isAlive == true else { return }
            Body.adjust(person, "stamina", Int64(cost) * Int64(r.staminaPerCost), &ctx)
        default:
            break
        }
    }
}
