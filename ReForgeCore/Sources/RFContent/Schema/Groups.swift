import RFKernel

/// 集団(勢力)の定義。名前は認識の表の `group:<id>`。持ち主: 統合担当(型)/ U5・U11(使う側)/ U14(中身)。
///
/// 世界を作るとき `PeopleState.groups[id]` に初めの関係と旗を入れる(知っているか `known` は false から)。
/// 人の初めの所属は `PersonDef.group`。関係・旗の変化は効果 groupRelation・groupFlag、見るのは条件 group・groupFlag・inGroup。
public struct GroupDef: Codable, Equatable, Sendable {
    public var id: GroupID
    /// 拠点との関係の初めの値(負は敵対)。既定 0。
    public var relation: Int?
    /// 初めに立っている旗。
    public var flags: [String]?

    public init(id: GroupID, relation: Int? = nil, flags: [String]? = nil) {
        self.id = id
        self.relation = relation
        self.flags = flags
    }
}

extension GroupDef: ContentDef {}
