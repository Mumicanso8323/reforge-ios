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
///  - 動く物(人・敵)は「前のマス・次のマス・進み具合」を持ち、画面が補間して滑らかに動かす。
///    シミュレーションのステップ(実時間でおよそ 10 回/秒)と描画のフレーム(60 回/秒)を切り離す。
///  - 文字は事実が変わったとき(ChangeSet.perception)だけ引き直す。
public struct Frame: Equatable, Sendable {
    /// 作るたびに増える番号。
    public var revision: Int
    public var clock: ClockView
    public var status: [StatusItem]
    public var map: MapView
    public var actors: [ActorSprite]
    public var placements: [PlacementSprite]
    /// 決断待ち(下の帯に出す。blocking のものだけ時計が止まっている)。
    public var decision: DecisionView?
    /// 流れている場面の行(地図の上に 3 行まで)。
    public var sceneLines: [String]
    /// 短い知らせ(足元カードの上に数秒)。
    public var notices: [String]
    /// 見え方が書き換わった物(「書き換わった」演出の対象)。
    public var renamed: [String]

    public init(revision: Int, clock: ClockView, status: [StatusItem], map: MapView, actors: [ActorSprite],
                placements: [PlacementSprite], decision: DecisionView?, sceneLines: [String], notices: [String],
                renamed: [String]) {
        self.revision = revision
        self.clock = clock
        self.status = status
        self.map = map
        self.actors = actors
        self.placements = placements
        self.decision = decision
        self.sceneLines = sceneLines
        self.notices = notices
        self.renamed = renamed
    }
}

public struct ClockView: Equatable, Sendable {
    public var day: Int
    public var phase: DayPhase
    /// 昼の残り(0...1000)。昼以外は 0。
    public var dayRemainingPermille: Int
    /// 時計が動くか(昼・続行中・止める決断なし)。
    public var running: Bool
}

/// 上の帯の 1 項目(食料あと 3 日・数値の段階・次の目標…)。
public struct StatusItem: Equatable, Sendable {
    public var key: String
    public var label: String
    public var value: String
    /// 危ない(赤く出す)。
    public var alert: Bool
}

public struct MapView: Equatable, Sendable {
    public var layer: LayerID
    public var size: GridSize
    public static let chunkSize = 16
    /// 区画(行優先)ごとの版。
    public var chunkRevisions: [Int]
}

/// 1 マスの見え方。
public struct TileView: Equatable, Sendable {
    public enum Fog: Sendable { case unknown, remembered, visible }
    public var glyph: String
    /// 色の名前(テーマの色の表のキー。認識の層の外)。
    public var tint: String
    public var fog: Fog
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
