import RFKernel

/// 画面の要素を出す条件(A Dark Room 式の段階的な解放)。条件は毎回評価する(状態は持たない)ので、
/// 知った事実・建てた物の数のような戻らない条件で書く。どの要素をいつ出すかの中身は非公開の層が決める。
public struct UIGateDef: ContentDef, Equatable {
    public var id: UIElementID
    public var when: Condition
    /// 一度開いたら開いたままにするか(W-01)。nil は毎回評価する(今までどおり)。
    /// 付いていれば、一度成り立った時に KnowledgeState.disclosed に理由と一緒に記録する。
    /// 巻き戻しでは .knowledge だけが残り、.world は巻き戻した先の世界に従う(INV-O4)。
    public var latch: DisclosureKind?

    public init(id: UIElementID, when: Condition, latch: DisclosureKind? = nil) {
        self.id = id
        self.when = when
        self.latch = latch
    }
}

extension TypedID where Tag == UIElementTag {
    /// 地図の足元の札に出る行為の要素。
    public static func interaction(_ i: InteractionID) -> UIElementID { UIElementID("interaction.\(i.rawValue)") }
}

/// 画面の要素の ID の一覧(1 か所だけ。U17・U18 の画面と、検証の uiGates.id が使う)。
/// 足すときはここに足す。"interaction.<InteractionID>" は一覧に書かず、行為の定義があるかで確かめる。
public enum UIElements {
    // 下のタブ(U18)
    public static let tabMap: UIElementID = "tab.map"
    public static let tabDesign: UIElementID = "tab.design"
    public static let tabNotes: UIElementID = "tab.notes"
    public static let tabBase: UIElementID = "tab.base"
    public static let tabCrew: UIElementID = "tab.crew"
    // 拠点・研究・仲間・戦闘・保存(U18)
    public static let baseStock: UIElementID = "base.stock"
    public static let baseBuild: UIElementID = "base.build"
    public static let baseLines: UIElementID = "base.lines"
    public static let research: UIElementID = "research"
    public static let crewAssign: UIElementID = "crew.assign"
    public static let crewRelation: UIElementID = "crew.relation"
    public static let combatStance: UIElementID = "combat.stance"
    public static let combatRetreat: UIElementID = "combat.retreat"
    public static let saveManual: UIElementID = "save.manual"
    /// 割り当ての種類ごと(crew.assign.<種類>)。種類は RFPresent の CrewMemberView.AssignKind の rawValue。
    public static let assignKinds = ["gather", "haul", "operate", "research", "guard", "build", "rest", "idle", "follow"]
    public static func assign(_ kind: String) -> UIElementID { UIElementID("crew.assign.\(kind)") }
    // 設計・ノート(U17)
    public static let designSheet: UIElementID = "design.sheet"
    public static let designTrial: UIElementID = "design.trial"
    public static let designPlate: UIElementID = "design.plate"
    public static let designHints: UIElementID = "design.hints"
    public static let notesTrials: UIElementID = "notes.trials"
    public static let notesCodex: UIElementID = "notes.codex"
    public static let notesClues: UIElementID = "notes.clues"
    public static let notesDocuments: UIElementID = "notes.documents"

    /// 一覧の全部(検証用)。
    public static let all: Set<UIElementID> = Set([
        tabMap, tabDesign, tabNotes, tabBase, tabCrew, baseStock, baseBuild, baseLines, research, crewAssign,
        crewRelation, combatStance, combatRetreat, saveManual, designSheet, designTrial, designPlate, designHints,
        notesTrials, notesCodex, notesClues, notesDocuments,
    ] + assignKinds.map(assign))

    /// その ID が画面のどこかの要素か(行為の要素は定義があるか)。
    public static func isKnown(_ id: UIElementID, in db: ContentDB) -> Bool {
        if all.contains(id) { return true }
        let p = "interaction."
        guard id.rawValue.hasPrefix(p) else { return false }
        return db.interactions[InteractionID(String(id.rawValue.dropFirst(p.count)))] != nil
    }
}
