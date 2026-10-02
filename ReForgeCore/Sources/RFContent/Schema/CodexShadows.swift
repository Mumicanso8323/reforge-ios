import RFKernel
import RFMatter

public enum CodexShadowTag {}
/// 図鑑の影の欄の ID。
public typealias CodexShadowID = TypedID<CodexShadowTag>

/// 図鑑の影の欄(答えは隠し、深さがあることは隠さない)。
///
/// - 名前だけの欄: まだ作っていない物の名前を影で出す。名前は認識の表の見出し(`name`)で引くので、
///   名前の部品(MatterName)に無い造語の名前も書ける。`target` があれば、作った名前がその部品を全部含んだとき埋まる。
/// - 品の欄(`item`): 持ったことのある品を、認識の層の名前のまま 1 行に出す(正体の分からない品は、
///   見え方の表がそう書く)。正体が分かったかどうかは `filledWhen` で書く。
/// どの欄を・いつ出すかの中身は非公開の層が決める。公開の層には試験用の欄だけを置く。
public struct CodexShadowDef: ContentDef, Equatable {
    public var id: CodexShadowID
    /// 欄の名前の見出し(認識の表)。
    public var name: SubjectID
    /// 影を出す条件(省略時はいつも)。
    public var when: Condition?
    /// 作れば埋まる名前(部品の一部でよい)。
    public var target: MatterName?
    /// 品の欄なら、その品(持ったことがあれば欄が出る)。
    public var item: ItemID?
    /// 埋まる条件(target を作ったこととは別に。品の正体が分かった、など)。
    public var filledWhen: Condition?
    /// 並び順(小さいほど上。同じなら id の順)。
    public var order: Int?

    public init(id: CodexShadowID, name: SubjectID, when: Condition? = nil, target: MatterName? = nil, item: ItemID? = nil,
                filledWhen: Condition? = nil, order: Int? = nil) {
        self.id = id
        self.name = name
        self.when = when
        self.target = target
        self.item = item
        self.filledWhen = filledWhen
        self.order = order
    }
}
