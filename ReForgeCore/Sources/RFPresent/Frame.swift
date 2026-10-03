import RFContent
import RFKernel
import RFMap
import RFMatter
import RFPerception
import RFRules
import RFWorld

/// 画面に渡す 1 枚の絵の材料(C-engine-ui.md §4)。すべて値型・文字列は認識の層を通した後のもの。
/// SwiftUI はこれだけを見る(WorldState を直接見ない)。
///
/// 60fps の描画を邪魔しないために:
///  - 地図は 16×16 の区画ごとの版(revision)を持ち、変わった区画だけ描き直す(区画の中身は MapChunk で引く)。
///    区画の版は「霧(未踏・既知・手がかり)と地形と目印」が変わったときだけ上がる。視界(いま見えている円)は
///    区画に入れず `MapView.vision` で別に渡す(歩くたびに区画を作り直さない。画面は円で切り抜いて明るく描く)。
///  - 動く物(人・敵)は「前のマス・次のマス・進み具合」を持ち、画面が補間して滑らかに動かす。
///    シミュレーションのステップ(実時間でおよそ 10 回/秒)と描画のフレーム(60 回/秒)を切り離す。
///  - 文字は事実が変わったとき(ChangeSet.perception)だけ引き直す。
public struct Frame: Equatable, Sendable {
    /// 作るたびに増える番号。
    public var revision: Int
    public var clock: ClockView
    public var status: [StatusItem]
    /// 次の目標(上の帯に 1 つ)。
    public var objective: String?
    public var map: MapView
    public var actors: [ActorSprite]
    public var placements: [PlacementSprite]
    /// ノアがこれから歩くマス(点線で描く。先頭が次のマス)。
    public var route: [GridPoint]
    /// 追従するマス(ノアの位置)。
    public var focus: GridPoint?
    /// 決断待ち(上の帯に出す。blocking のものだけ時計が止まっている)。
    public var decision: DecisionView?
    /// 流れている場面の行(地図の上のふきだしに 3 行まで)。
    public var sceneLines: [String]
    /// 冒頭の文章を読んでいる間だけある。地図と通常の操作は隠す。
    public var prologue: PrologueView?
    /// 最初の行為まで、地図の代わりに出す操作。
    public var darkStart: DarkStartView?
    /// 短い知らせ(足元カードの上に数秒)。
    public var notices: [String]
    /// 見え方が書き換わった物(「書き換わった」演出の対象)。
    public var renamed: [String]
    /// 走行が終わった(ゲームオーバーの 4 択を出す)。
    public var runEnded: Bool
    /// 設計・ノートのタブが引き直す印(在庫・ノート・知識などが変わった・日が変わったときに上がる)。
    public var benchRevision: Int = 0
    /// 画面の要素の解放(U18。表に無い要素はいつも出す)。
    public var ui: UIUnlocks = UIUnlocks()
    /// 進行中の戦闘(上の帯と地図に出す。止めない)。
    public var battles: [BattleBand] = []
    /// 地図の題(INV-O12)。認識の層の主題 place:base の今の名前。見え方の表に無ければ nil(題を出さない)。
    /// 状態を別に持たないので、点火と同じステップの事実で、同じフレームのうちに変わる。
    public var placeTitle: String?
    /// 前のフレームから新しく開いた画面の要素(W-07。画面が一度だけ光らせる)。前のフレームが無ければ空。
    public var newlyOpened: Set<UIElementID> = []
    /// 半分の気配の影の行(HNT-17)。まだ解放されていない建造物とモジュールのうち、HintRule.halfway が真のもの。
    /// 押せない。「まだ作り方を知らない」と出し、解放の条件は書かない。
    public var shadows: [ShadowRow] = []
    /// 戦闘が始まったときの方針(寝ている間の戦闘もこれ)。
    public var defaultStance: BattleState.Stance = .keepDistance
    /// 夜の締めの 3 行(PT-B2)。日没(夜作業か寝るかを選ぶ帯が出ている間)だけ入る。
    public var dayWrap: DayWrapView?
    /// ノアが自分で歩ける範囲(行ごとの横の範囲。視界の rowSpans と同じ形)。画面は縁を細い線で描く。
    public var walkable: [WalkSpan] = []
    /// 操作棒を出してよいか(地図が灯っていて、戦闘中・眠っている間ではないとき)。画面は自分で判断しない。
    public var canSteer: Bool = false

    public init(revision: Int, clock: ClockView, status: [StatusItem], objective: String? = nil, map: MapView,
                actors: [ActorSprite], placements: [PlacementSprite], route: [GridPoint] = [], focus: GridPoint? = nil,
                decision: DecisionView?, sceneLines: [String], notices: [String], renamed: [String],
                runEnded: Bool = false, prologue: PrologueView? = nil, darkStart: DarkStartView? = nil) {
        self.revision = revision
        self.clock = clock
        self.status = status
        self.objective = objective
        self.map = map
        self.actors = actors
        self.placements = placements
        self.route = route
        self.focus = focus
        self.decision = decision
        self.sceneLines = sceneLines
        self.prologue = prologue
        self.darkStart = darkStart
        self.notices = notices
        self.renamed = renamed
        self.runEnded = runEnded
    }
}

public struct PrologueView: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case prologue
        case stage
    }

    public var kind: Kind
    public var lines: [String]
    /// lines と同じ添字の話し手。nil の行には名前を出さない。
    public var speakers: [String?]
    public var waiting: Bool
    public var art: ArtID?

    public init(kind: Kind = .prologue, lines: [String], speakers: [String?] = [], waiting: Bool, art: ArtID? = nil) {
        self.kind = kind
        self.lines = lines
        self.speakers = speakers
        self.waiting = waiting
        self.art = art
    }
}

/// 最初の行為まで、地図を開かずに出す 1 つの操作。
/// 歩ける範囲の 1 行(y 行の minX...maxX)。
public struct WalkSpan: Equatable, Sendable {
    public var y: Int
    public var minX: Int
    public var maxX: Int

    public init(y: Int, minX: Int, maxX: Int) {
        self.y = y
        self.minX = minX
        self.maxX = maxX
    }
}

public struct DarkStartView: Equatable, Sendable {
    public var action: FootCard.Action

    public init(action: FootCard.Action) {
        self.action = action
    }
}

public struct ClockView: Equatable, Sendable {
    public var day: Int
    public var phase: DayPhase
    /// 昼の残り(0...1000)。昼以外は 0。
    public var dayRemainingPermille: Int
    /// 時計が動くか(昼・続行中・止める決断なし)。
    public var running: Bool
    /// 最初の行為まで時計を止めている(W-01)。この間は上の帯に日の残りを出さない。
    public var held: Bool = false
    /// 日の残りを出すか(U20。時計を止めている間と、band.day の門が閉じている間は false)。
    public var showsDayLeft: Bool = true
    /// 日没の帯に出す、焚き火の見込み(薪の置き場に残る本数ぶんを入れて 4 段。PT-B1)。日没・夜作業で、焚き火がある間だけ。
    public var fireOutlook: FireOutlook?

    public init(day: Int, phase: DayPhase, dayRemainingPermille: Int, running: Bool) {
        self.day = day
        self.phase = phase
        self.dayRemainingPermille = dayRemainingPermille
        self.running = running
    }

    /// 夜(暗く描く・視界が狭い)か。
    public var isNight: Bool { phase != .day }

    /// 上の帯に出す時間の選択(日没: 夜作業 / 寝る、夜作業: 寝る)。全画面のシートで止めない。
    public var bandActions: [BandAction] {
        switch phase {
        case .day: []
        case .dusk: [.startNightWork, .sleep]
        case .nightWork: [.sleep]
        }
    }
}

/// 上の帯で選ぶ時間の操作。文言は画面の固定文言(Localizable)。
public enum BandAction: String, Equatable, Sendable, CaseIterable {
    case startNightWork
    case sleep

    public var command: Command {
        switch self {
        case .startNightWork: .time(.startNightWork)
        case .sleep: .time(.sleep)
        }
    }
}

/// 上の帯の 1 項目(食料あと 3 日・数値の段階…)。
public struct StatusItem: Equatable, Sendable {
    public var key: String
    public var label: String
    public var value: String
    /// 危ない(赤く出す)。
    public var alert: Bool
    /// 棒と目盛り(見え方が showMarks のときだけ。U18)。
    public var gauge: StatGauge? = nil

    public init(key: String, label: String, value: String, alert: Bool) {
        self.key = key
        self.label = label
        self.value = value
        self.alert = alert
    }
}

public struct MapView: Equatable, Sendable {
    public var layer: LayerID
    public var size: GridSize
    public static let chunkSize = 16
    /// 区画(行優先)ごとの版。
    public var chunkRevisions: [Int]
    /// 区画の中身の指紋(版を上げるかの判定に使う。画面は見なくてよい)。
    public var chunkSignatures: [Int]
    /// いま見えている範囲(一員ごとの円)。この中は明るく、物と生き物も描く。
    public var vision: [VisionArea]
    /// 地図の光の点(この層のもの。id の順)。暗闇・霧の中でも描く(効果 beacon。U19)。
    public var beacons: [GridPoint] = []

    public init(layer: LayerID, size: GridSize, chunkRevisions: [Int], chunkSignatures: [Int] = [],
                vision: [VisionArea] = []) {
        self.layer = layer
        self.size = size
        self.chunkRevisions = chunkRevisions
        self.chunkSignatures = chunkSignatures
        self.vision = vision
    }

    /// 横・縦の区画の数。
    public var chunkColumns: Int { (size.width + Self.chunkSize - 1) / Self.chunkSize }
    public var chunkRows: Int { (size.height + Self.chunkSize - 1) / Self.chunkSize }

    /// マスを含む区画の番号(地図の外は nil)。
    public func chunkIndex(of p: GridPoint) -> Int? {
        guard size.contains(p) else { return nil }
        return (p.y / Self.chunkSize) * chunkColumns + p.x / Self.chunkSize
    }

    /// 区画の範囲(端の区画は小さい)。
    public func chunkRect(_ index: Int) -> GridRect {
        let cs = Self.chunkSize
        let ox = (index % max(1, chunkColumns)) * cs
        let oy = (index / max(1, chunkColumns)) * cs
        return GridRect(origin: GridPoint(ox, oy),
                        size: GridSize(width: min(cs, size.width - ox), height: min(cs, size.height - oy)))
    }

    /// 範囲に重なる区画の番号(描くときに使う)。
    public func chunks(overlapping r: GridRect) -> [Int] {
        let cs = Self.chunkSize
        let x0 = max(0, r.origin.x) / cs, y0 = max(0, r.origin.y) / cs
        let x1 = min(size.width - 1, r.origin.x + r.size.width - 1), y1 = min(size.height - 1, r.origin.y + r.size.height - 1)
        guard x1 >= 0, y1 >= 0, x1 >= r.origin.x, y1 >= r.origin.y else { return [] }
        var out: [Int] = []
        for cy in y0...(y1 / cs) { for cx in x0...(x1 / cs) { out.append(cy * chunkColumns + cx) } }
        return out
    }

    /// いま見えているマスか。
    public func isVisible(_ p: GridPoint) -> Bool { vision.contains { $0.contains(p) } }
}

/// 1 マスの見え方。
public struct TileView: Hashable, Sendable {
    public enum Fog: Hashable, Sendable {
        /// 未踏(黒)。
        case unknown
        /// 前に見た(暗い地形だけ)。
        case remembered
        /// 視界の中(区画には入らない。FrameBuilder.tile で引いたときだけ)。
        case visible
        /// 未踏だが霧の端に手がかりの影(「？」・残骸の影)が見える。
        case hint
    }

    /// 見えたときの文字(1 文字)。
    public var glyph: String
    /// 色の名前(TilePalette のキー。認識の層の外)。
    public var tint: String
    public var fog: Fog
    /// 手がかりの影の文字(fog == .hint のとき)。
    public var shadow: String?
    /// 暗闇でも描く光る印(見え方の glow)。夜の灯りの外でも、既知か手がかりのマスなら描く。
    public var glow: Bool

    public init(glyph: String, tint: String, fog: Fog, shadow: String? = nil, glow: Bool = false) {
        self.glyph = glyph
        self.tint = tint
        self.fog = fog
        self.shadow = shadow
        self.glow = glow
    }

    public static let void = TileView(glyph: "", tint: TilePalette.void, fog: .unknown)
}

/// 区画 1 つの中身(画面がキャッシュし、版が変わったら引き直す)。
public struct MapChunk: Equatable, Sendable {
    public var index: Int
    public var revision: Int
    public var rect: GridRect
    /// 行優先(rect.size の大きさ)。
    public var tiles: [TileView]

    public init(index: Int, revision: Int, rect: GridRect, tiles: [TileView]) {
        self.index = index
        self.revision = revision
        self.rect = rect
        self.tiles = tiles
    }

    public func tile(at p: GridPoint) -> TileView? {
        guard rect.contains(p) else { return nil }
        return tiles[(p.y - rect.origin.y) * rect.size.width + (p.x - rect.origin.x)]
    }
}

public struct ActorSprite: Equatable, Sendable {
    public var id: String
    public var glyph: String
    public var from: GridPoint
    public var to: GridPoint
    /// from → to の進み(0...1000)。画面がフレームごとに補間する。
    public var progress: Int
    public var facing: Direction
    public var label: String
    /// ノア(追従と色の対象)。
    public var isNoah: Bool
    /// 拠点の一員(視界の外でも描く)。
    public var isMember: Bool
    /// 色の名前(TilePalette)。
    public var tint: String

    public init(id: String, glyph: String, from: GridPoint, to: GridPoint, progress: Int, facing: Direction,
                label: String, isNoah: Bool = false, isMember: Bool = true, tint: String = TilePalette.member) {
        self.id = id
        self.glyph = glyph
        self.from = from
        self.to = to
        self.progress = progress
        self.facing = facing
        self.label = label
        self.isNoah = isNoah
        self.isMember = isMember
        self.tint = tint
    }

    /// 向き付きの主人公の文字(原作 MapScreen.cs の ↑→↓←)。
    public static func arrow(_ d: Direction) -> String {
        switch d {
        case .north: "↑"
        case .east: "→"
        case .south: "↓"
        case .west: "←"
        }
    }
}

public struct PlacementSprite: Equatable, Sendable {
    public var id: EntityID
    public var glyph: String
    public var at: GridPoint
    public var facing: Direction
    public var running: Bool
    /// 止まっている理由(ふきだし)。
    public var stoppedReason: String?
    /// 1 日あたりの入/出。
    public var throughput: String?

    public init(id: EntityID, glyph: String, at: GridPoint, facing: Direction, running: Bool, stoppedReason: String?,
                throughput: String?) {
        self.id = id
        self.glyph = glyph
        self.at = at
        self.facing = facing
        self.running = running
        self.stoppedReason = stoppedReason
        self.throughput = throughput
    }
}

public struct DecisionView: Equatable, Sendable {
    public var id: EntityID
    public var blocking: Bool
    public var choices: [(id: ChoiceID, label: String)]
    /// 問いの文(無い決断は nil)。
    public var prompt: String?

    public static func == (a: Self, b: Self) -> Bool {
        a.id == b.id && a.blocking == b.blocking && a.prompt == b.prompt && a.choices.map(\.id) == b.choices.map(\.id)
            && a.choices.map(\.label) == b.choices.map(\.label)
    }
}

/// 工程表(設計画面の部品で開く表。REQ: ライン専用にしない)。ライン札・試作・コンテンツの記録(SheetDef)を同じ形で出す。
public struct ProcessSheet: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        case design(EntityID)
        case trial(ProvenanceID)
        case record(SheetID)
        /// 記録の並びの 1 件(席の番号)。開くと試作と同じ形の工程表になる。
        case recordEntry(SheetID, slot: Int)
        /// 設計画面の下書き(まだ試しても札にしてもいない並び)。input は試すつもりの在庫の山(見込みの照合に使う)。
        case draft(steps: [ProcessStep], input: StockSelector?)
    }

    /// 物の見え方(名前と、ノアの手の見当の百分率)。見当の言い回し(「三割くらい」)は画面の固定文言で組む。
    public struct Sensed: Equatable, Sendable {
        public var name: String
        /// ノアの手の見当(0〜100。刻みは HandSense)。
        public var percent: Int

        public init(name: String, percent: Int) {
            self.name = name
            self.percent = percent
        }
    }

    /// 試作の結果カード(物・見当・硬さ・粘り・副産物・所見・使った物)。
    public struct Card: Equatable, Sendable {
        public struct Used: Equatable, Sendable {
            public var name: String
            public var quantity: Int
        }
        public var product: Sensed
        public var hardness: Int
        public var toughness: Int
        public var byproducts: [String]
        public var findings: [String]
        public var used: [Used]
        public var quantity: Int
        /// 唯一品になった(最初の 1 個など)。
        public var unique: Bool
    }

    public struct Row: Equatable, Sendable {
        public var title: String
        public var note: String?
        /// 記録の並びの席の番号(番号の書き方は画面の固定文言)。
        public var slot: Int?
        /// 空いた席(記録が無い)。
        public var empty: Bool = false
        /// 行の横の数(鍛えた量・最高の純度など)。
        public var figure: Int?
        /// 答えを置ける行の名前(placeAnswer に渡す)。
        public var answerRow: String?
        /// 置いた答え(来歴の 1 行)。
        public var answer: String?
        /// 選ぶ表: 含める(true)/ 含めない(false)/ まだ(nil)。
        public var included: Bool?
        /// 選ぶ表: 本人が言った「含める / 含めない」。
        public var declared: Bool?
        /// 選ぶ表・工程表: その人。
        public var person: PersonID?
        /// 工程の行なら、その段の番号(0 始まり)。設計画面が段を入れ替え・外すのに使う。
        public var step: Int?
        /// この段を通った後の見込み(同じ入力・同じ並びを試したことがあるときだけ。nil は「？」)。
        public var forecast: Sensed?
        /// この段で載った所見(文)。
        public var findings: [String] = []
        /// 工程の段に入れた物の名前(並べ方・区切りは画面が言語に合わせる)。
        public var inputs: [String] = []

        public init(title: String, note: String?, slot: Int? = nil, empty: Bool = false, figure: Int? = nil,
                    answerRow: String? = nil, answer: String? = nil, included: Bool? = nil, declared: Bool? = nil,
                    person: PersonID? = nil) {
            self.title = title
            self.note = note
            self.slot = slot
            self.empty = empty
            self.figure = figure
            self.answerRow = answerRow
            self.answer = answer
            self.included = included
            self.declared = declared
            self.person = person
        }
    }

    /// 記録の並びの数(記録のある席 / 席の数)。空いた席が数えられる。
    public struct Tally: Equatable, Sendable {
        public var filled: Int
        public var slots: Int

        public init(filled: Int, slots: Int) {
            self.filled = filled
            self.slots = slots
        }
    }

    public var source: Source
    public var title: String
    public var rows: [Row]
    /// 結果(試作・ライン札のとき。記録の 1 件なら名前)。
    public var result: String?
    public var tally: Tally?
    /// 表の頭(入力の物と見当)。試作・下書き・試したことのあるライン札のとき。
    public var head: Sensed?
    /// 並び全体の見込み(下書き・ライン札。同じ並びを試していなければ nil)。
    public var expected: Sensed?
    /// 試作の結果カード(試作の表のとき)。
    public var card: Card?
    /// 工程表で技能を付けられる表なら、その候補(使える条件が成り立っているときだけ)。
    public var grant: SkillGrant?
    /// 選ぶ表なら、確定したか(選ぶ表でなければ nil)。
    public var rosterConfirmed: Bool?

    /// 工程表の候補(付けられる技能と、付けられる人)。
    public struct SkillGrant: Equatable, Sendable {
        public struct Skill: Equatable, Sendable {
            public var id: SkillID
            public var name: String
        }
        public struct Target: Equatable, Sendable {
            public var person: PersonID
            public var name: String
            /// この表で付けた技能の名前。
            public var written: [String]
            /// 未選択の状態(true = 本人が断った / false = 付けないと決めた / nil = まだ)。
            public var declined: Bool?
        }
        public var skills: [Skill]
        public var targets: [Target]
    }

    /// Labels supplied by the content text table for sheet controls.
    public struct Labels: Equatable, Sendable {
        public var rosterInclude: String
        public var rosterExclude: String
        public var rosterConfirm: String
        public var rosterConfirmHint: String
        public var grantTitle: String
        public var grantSkip: String
        public var grantRefused: String

        public init(rosterInclude: String, rosterExclude: String, rosterConfirm: String, rosterConfirmHint: String,
                    grantTitle: String, grantSkip: String, grantRefused: String) {
            self.rosterInclude = rosterInclude
            self.rosterExclude = rosterExclude
            self.rosterConfirm = rosterConfirm
            self.rosterConfirmHint = rosterConfirmHint
            self.grantTitle = grantTitle
            self.grantSkip = grantSkip
            self.grantRefused = grantRefused
        }
    }

    public var labels: Labels?

    public init(source: Source, title: String, rows: [Row], result: String?, tally: Tally? = nil,
                head: Sensed? = nil, expected: Sensed? = nil, card: Card? = nil) {
        self.source = source
        self.title = title
        self.rows = rows
        self.result = result
        self.tally = tally
        self.head = head
        self.expected = expected
        self.card = card
    }
}

/// 答えの候補(来歴の 1 件)。
public struct AnswerCandidate: Equatable, Sendable {
    public var record: ProvenanceID
    public var label: String
}

/// 長押しで調べたマス(ふきだし)。数の言い回し(「残り 3 回」「三割くらい」)は画面の固定文言で組む。
public struct TileInspection: Equatable, Sendable {
    public enum Line: Equatable, Sendable {
        /// 鉱脈の見た目の名前など。
        case name(String)
        /// 鉱脈の残り回数。
        case remaining(Int)
        /// ノアの手ざわり(純度の見当。1〜10 割)。
        case purityTenths(Int)
    }

    public var point: GridPoint
    public var title: String
    public var lines: [Line]

    public init(point: GridPoint, title: String, lines: [Line]) {
        self.point = point
        self.title = title
        self.lines = lines
    }
}

/// 足元カード(注目しているマスの名前と、できること 1〜3 個)。
public enum FootCardState: String, Equatable, Sendable {
    case empty
    case unseen
    case far
    case busy
    case normal
}

public struct FootCard: Equatable, Sendable {
    public struct Action: Equatable, Sendable {
        public var id: InteractionID
        public var label: String
        /// 押し続ける行為(押している間 holding)。
        public var hold: Bool
        public var at: WorldPoint
        /// 行為の対象のマス(ノアのマスか、手の届く隣のマス)。
        public var target: GridPoint
        /// いまの 1 単位の進み(0...1000)。押していないときは nil(PT-B3 のバーもこれを読む)。
        public var progressPermille: Int?

        public init(id: InteractionID, label: String, hold: Bool, at: WorldPoint, progressPermille: Int? = nil) {
            self.id = id
            self.label = label
            self.hold = hold
            self.at = at
            self.target = at.point
            self.progressPermille = progressPermille
        }

        /// 始める(押し始め・タップ)。
        public var start: Command { .exploration(.interact(interaction: id, at: at, holding: true)) }
        /// 押し続ける行為を離した。
        public var end: Command { .exploration(.interact(interaction: id, at: at, holding: false)) }
    }

    public static let maxActions = 3

    public var point: GridPoint
    public var title: String
    public var actions: [Action]
    /// 画面がそのまま見せる状態。画面側で距離や作業中を推測しない。
    public var state: FootCardState = .normal
    /// いまのページ(0 から)と全ページ数。行為は 1 ページに最大 maxActions 個(4 つ目からは次のページ)。
    public var page: Int = 0
    public var pageCount: Int = 1
    /// 押せる物がない理由、または次にすることを示す短い一行。
    public var hint: String?
    /// このマスの残骸から開ける資料(段階つきの資料など。行為の数には数えない。U18)。
    public var documents: [DocumentLink] = []
    /// 焚き火の足元カードの、火の見込み(今と、1 本くべた後)。焚き火でなければ nil(PT-B1)。
    public var fire: FireOutlookView?
    /// 続けて採っていて「近くにもう無い」で止まった直後か(足元カードに固定の文言を出す。PT-B1)。
    public var nothingNearby: Bool = false

    public struct DocumentLink: Equatable, Sendable {
        public var id: DocumentID
        public var title: String

        public init(id: DocumentID, title: String) {
            self.id = id
            self.title = title
        }
    }

    public init(point: GridPoint, title: String, actions: [Action]) {
        self.point = point
        self.title = title
        self.actions = actions
    }
}

/// 焚き火の足元カードの、火の見込み 1 行(「今: 夜半 → 1 本くべると: 夜明けまでもつ」)。
public struct FireOutlookView: Equatable, Sendable {
    public var now: FireOutlook
    public var afterOneMore: FireOutlook

    public init(now: FireOutlook, afterOneMore: FireOutlook) {
        self.now = now
        self.afterOneMore = afterOneMore
    }
}

/// 数値の棒と目盛り(千分率の位置。目盛りの意味は書かない)。
public struct StatGauge: Equatable, Sendable {
    /// 棒の満ち(0...1000)。
    public var fillPermille: Int
    /// 目盛りの位置(0...1000)。
    public var marks: [Int]

    public init(fillPermille: Int, marks: [Int]) {
        self.fillPermille = fillPermille
        self.marks = marks
    }

    /// 値と目盛り(どちらも raw)から。一番大きな目盛りが右端の手前(1/11 の余白)に来る。
    public static func make(value: Int64, marks: [Int]) -> StatGauge? {
        guard let top = marks.max(), top > 0 else { return nil }
        let scale = Int64(top) + Int64(top) / 10
        func pos(_ v: Int64) -> Int { Int(max(0, min(1000, v * 1000 / max(1, scale)))) }
        return StatGauge(fillPermille: pos(value), marks: marks.sorted().map { pos(Int64($0)) })
    }
}

/// 半分の気配の影の行 1 つ(HNT-17・W-07)。押せない。
public struct ShadowRow: Equatable, Sendable {
    public var kind: PlaceableKind
    /// 今の呼び名(認識の層)。
    public var name: String
    /// 費用の合計と、いま持っている数(費用ごとに上限で切った和)。
    public var have: Int
    public var need: Int

    public init(kind: PlaceableKind, name: String, have: Int, need: Int) {
        self.kind = kind
        self.name = name
        self.have = have
        self.need = need
    }
}
