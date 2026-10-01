import RFKernel
import RFMatter

// 発明(RFInvention)の定義の部品。持ち主: U6 発明。
// 手がかり(HintDef)が「何を言っているか」を、文とは別に機械が読める形で持つ。
// 文は非公開の文字列表にあり、ここは意味だけ(ID と並び)。
//
// 使い道:
// - 「手がかりは嘘をつかない」検査: 目標ごとの手がかりを全部満たす並びが、規則の表(RuleBook)で本当に目標に届く。
// - 推理ボット(TEST-R1-01): プレイヤーが文を読んで分かることを、ボットはこの形で読む。
// ノートは手がかりの文と出典を載せるだけで、規則をまとめない(推理はプレイヤーに残す)。

/// 工程の 1 段の型。モジュールと、入れた物(nil は問わない)。
public struct StepPattern: Codable, Hashable, Sendable {
    public var module: ModuleKindID
    public var input: ItemID?

    public init(_ module: ModuleKindID, input: ItemID? = nil) {
        self.module = module
        self.input = input
    }

    public func matches(_ s: ProcessStep) -> Bool {
        guard s.module == module else { return false }
        guard let input else { return true }
        return s.inputItems.contains(input)
    }
}

/// 手がかりが言っていること 1 つ。
public enum ClaimKind: Codable, Hashable, Sendable {
    /// その段がある(「石灰石を入れれば」)。
    case includes(step: StepPattern)
    /// その段を使わない。
    case excludes(step: StepPattern)
    /// 両方あるなら first が先(「混ぜ物は熱する前ね」)。片方しか無い並びには何も言わない。
    case before(first: StepPattern, then: StepPattern)
    /// first のすぐ後に then(「砕いて洗えば」)。first がある並びでだけ効く。
    case next(first: StepPattern, then: StepPattern)
    /// 名前の段の意味(命名からの類推: 「精」= 純度 threshold 以上)。工程の並びについては何も言わない。
    case gradeMeans(threshold: Purity)

    /// 並びがこの主張に合うか。並びについて何も言わない主張は nil。
    public func holds(in steps: [ProcessStep]) -> Bool? {
        switch self {
        case .includes(let p): return steps.contains(where: p.matches)
        case .excludes(let p): return !steps.contains(where: p.matches)
        case .before(let a, let b):
            // a の最後の出現が b の最初の出現より前(繰り返しの並びでも順番が崩れていない)
            guard let lastA = steps.lastIndex(where: a.matches), let firstB = steps.firstIndex(where: b.matches) else {
                return true
            }
            return lastA < firstB
        case .next(let a, let b):
            for (i, s) in steps.enumerated() where a.matches(s) {
                guard i + 1 < steps.count, b.matches(steps[i + 1]) else { return false }
            }
            return true
        case .gradeMeans: return nil
        }
    }
}

/// 手がかりの主張 1 つと、それが何に向けた話か。
public struct HintClaim: Codable, Hashable, Sendable {
    public var says: ClaimKind
    /// どの名前の部品に向けた話か(精 = grade fine、剛 = temper hard など)。nil は全般。
    public var toward: NamePart?

    public init(_ says: ClaimKind, toward: NamePart? = nil) {
        self.says = says
        self.toward = toward
    }
}

/// 工程の段を試作で使うのに要る条件(ModuleDef.trial)。設備が世界(置いた物・建てた物・地形)にあるかを Condition で書く。
/// 満たさないとき、試作は reason で断る(画面は足元カードに 1 行)。条件なしにするなら when に always を書く。
public struct TrialRequirement: Codable, Hashable, Sendable {
    public var when: Condition
    public var reason: TextID

    public init(when: Condition, reason: TextID) {
        self.when = when
        self.reason = reason
    }
}
