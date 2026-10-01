import RFKernel

/// 発明が来歴に付ける印。コンテンツの条件・出来事がこの ID で指す(物語の「最初の鉄」など)。
///
/// 例(コンテンツ): 最初の鉄の出来事の引き金
///   {"on": ["trialed"], "when": {"firstTime": {"query": {"act": "trialed", "tag": "tag.invention.smelted"}}}}
/// または {"ledger": {"query": {"tag": "tag.invention.first_smelt"}, "atLeast": 1}}
public enum InventionTags {
    /// 試作で鉱石が溶けて金属になった(製錬に成功した)。
    public static let smelted: ProvenanceTag = "tag.invention.smelted"
    /// 初めての製錬(ledger にまだ smelted の記録が無かった)。できた物は唯一品として残る。
    public static let firstSmelt: ProvenanceTag = "tag.invention.first_smelt"
}

/// 断った理由(文字列表のキー)。画面は足元カードに 1 行出す。
public enum InventionReasons {
    public static let noSteps: TextID = "reason.invention.no_steps"
    public static let badQuantity: TextID = "reason.invention.bad_quantity"
    public static let moduleLocked: TextID = "reason.invention.module_locked"
    public static let notMaterial: TextID = "reason.invention.not_material"
    public static let notEnoughInput: TextID = "reason.invention.not_enough_input"
    public static let missingInput: TextID = "reason.invention.missing_input"
    public static let noDesign: TextID = "reason.invention.no_design"
}

/// 工程表の題(文字列表のキー)。コンテンツの記録(SheetDef)の題は認識の表の見出し。
public enum InventionTexts {
    public static let designSheet: TextID = "text.sheet.design"
    public static let trialSheet: TextID = "text.sheet.trial"
    public static let draftSheet: TextID = "text.sheet.draft"
}
