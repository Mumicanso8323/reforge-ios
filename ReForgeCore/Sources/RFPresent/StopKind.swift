import RFKernel

/// 文ではなく印と色で見せる止まり方。
public enum StopKind: Equatable, Sendable {
    case wasteFull

    /// 印で見せない理由は nil。
    public static func of(reason: TextID) -> StopKind? {
        reason == "reason.module.waste_full" ? .wasteFull : nil
    }
}
