import RFContent
import RFKernel
import RFMap
import RFPerception
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
    /// 短い知らせ(足元カードの上に数秒)。
    public var notices: [String]
    /// 見え方が書き換わった物(「書き換わった」演出の対象)。
    public var renamed: [String]
    /// 走行が終わった(ゲームオーバーの 4 択を出す)。
    public var runEnded: Bool

    public init(revision: Int, clock: ClockView, status: [StatusItem], objective: String? = nil, map: MapView,
                actors: [ActorSprite], placements: [PlacementSprite], route: [GridPoint] = [], focus: GridPoint? = nil,
                decision: DecisionView?, sceneLines: [String], notices: [String], renamed: [String],
                runEnded: Bool = false) {
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
        self.notices = notices
        self.renamed = renamed
        self.runEnded = runEnded
    }
}

public struct ClockView: Equatable, Sendable {
    public var day: Int
    public var phase: DayPhase
    /// 昼の残り(0...1000)。昼以外は 0。
    public var dayRemainingPermille: Int
    /// 時計が動くか(昼・続行中・止める決断なし)。
    public var running: Bool

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

    public init(glyph: String, tint: String, fog: Fog, shadow: String? = nil) {
        self.glyph = glyph
        self.tint = tint
        self.fog = fog
        self.shadow = shadow
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

    public static func == (a: Self, b: Self) -> Bool {
        a.id == b.id && a.blocking == b.blocking && a.choices.map(\.id) == b.choices.map(\.id)
            && a.choices.map(\.label) == b.choices.map(\.label)
    }
}

/// 工程表(設計画面の部品で開く表。REQ: ライン専用にしない)。ライン札・試作・コンテンツの記録(SheetDef)を同じ形で出す。
public struct ProcessSheet: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        case design(EntityID)
        case trial(ProvenanceID)
        case record(SheetID)
    }

    public struct Row: Equatable, Sendable {
        public var title: String
        public var note: String?

        public init(title: String, note: String?) {
            self.title = title
            self.note = note
        }
    }

    public var source: Source
    public var title: String
    public var rows: [Row]
    /// 結果(試作・ライン札のとき)。
    public var result: String?
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
public struct FootCard: Equatable, Sendable {
    public struct Action: Equatable, Sendable {
        public var id: InteractionID
        public var label: String
        /// 押し続ける行為(押している間 holding)。
        public var hold: Bool
        public var at: WorldPoint

        public init(id: InteractionID, label: String, hold: Bool, at: WorldPoint) {
            self.id = id
            self.label = label
            self.hold = hold
            self.at = at
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

    public init(point: GridPoint, title: String, actions: [Action]) {
        self.point = point
        self.title = title
        self.actions = actions
    }
}
