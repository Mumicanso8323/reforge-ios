import Foundation
import RFContent
import RFKernel
import RFMatter
import RFWorld

/// 認識の層。プレイヤーに見える名前・説明・数値の見せ方を、真実の ID と「いま知っている事実の集合」から引く
/// (結合設計 MECH-02 / REQ-S7)。
///
/// - 名前は保存しない。毎回ここで引くので、事実を 1 つ知った瞬間に、既に作った物・置いた物・図鑑・ノートの
///   出典・地図のラベル・過去の記録(日誌)の名前が全部、新しい見え方になる(遡る書き換え)。
///   開示の本体は世界の状態を変える効果の側で、この層はそれを支える側。
/// - ここが返す文字列だけが画面に出る。英語の ID・見出しは決して返さない(見え方が無ければ unknownText)。
/// - 監査つき(auditor を渡す)で作ると、外へ返す文字列をすべて禁止語の規則と英語の ID の検査に当て、
///   違反を auditor に残す(ボット走行のテストで漏れを捕まえる。E-content.md §5.2 の 2)。
public struct Perceiver: Sendable {
    public let content: ContentDB
    public let known: Set<FactID>
    /// 走行中の監査(nil なら調べない。アプリの通常の描画では nil)。
    public let auditor: PerceptionAuditor?

    /// 見え方の無い見出しに出す文字列のキー。
    public static let unknownText: TextID = "text.unknown"

    public init(content: ContentDB, known: Set<FactID>, auditor: PerceptionAuditor? = nil) {
        self.content = content
        self.known = known
        self.auditor = auditor
    }

    public init(content: ContentDB, world: WorldState, auditor: PerceptionAuditor? = nil) {
        self.init(content: content, known: world.knowledge.factSet, auditor: auditor)
    }

    // MARK: 見え方

    /// いま使う見え方(見出しが表に無ければ nil)。
    public func variant(_ s: SubjectID) -> Variant? {
        content.perception[s]?.variants.first { $0.when.evaluate(known) }
    }

    /// いま使う見え方の番号(表の上から)。見え方が変わったかを比べるのに使う。
    public func variantIndex(_ s: SubjectID) -> Int? {
        content.perception[s]?.variants.firstIndex { $0.when.evaluate(known) }
    }

    public func name(_ s: SubjectID) -> String {
        audited(rawName(s), origin: s.rawValue)
    }

    public func description(_ s: SubjectID) -> String? {
        variant(s)?.description.map { audited(rawText($0), origin: s.rawValue) }
    }

    /// 文字列表から引き、{名前} を埋める。キーが表に無ければ unknownText(英語のキーは出さない)。
    public func text(_ id: TextID, _ args: [String: String] = [:]) -> String {
        audited(rawText(id, args), origin: id.rawValue)
    }

    // MARK: 品の色の系統

    /// 見出しのいまの見え方に付いた色の系統(無ければ中立)。真実の素材では分岐しない。
    public func tint(_ s: SubjectID) -> ItemTint {
        variant(s)?.tint ?? .neutral
    }

    /// 品・物質の色の系統。物質は主成分の名前の部品(substance:<ID>)の見え方から引く。
    public func tint(of stuff: Stuff) -> ItemTint {
        switch stuff {
        case .item(let i): tint(Subject.item(i))
        case .matter(let m): tint(Subject.namePart(.substance(m.substance)))
        }
    }

    // MARK: 物・置いた物・人

    /// 物質の名前(名前の部品を 1 つずつ引いて連結する)。図鑑・在庫・試作の結果で同じ関数を使う。
    public func name(of name: MatterName) -> String {
        audited(rawName(of: name), origin: "matter")
    }

    public func name(of stuff: Stuff, naming: (Matter) -> MatterName = { NameGenerator.name(for: $0) }) -> String {
        switch stuff {
        case .item(let i): name(Subject.item(i))
        case .matter(let m): name(of: naming(m))
        }
    }

    /// 置いた物(モジュール・建造物)の名前。
    public func name(of kind: PlaceableKind) -> String {
        name(Self.subject(of: kind))
    }

    public static func subject(of kind: PlaceableKind) -> SubjectID {
        switch kind {
        case .module(let k): Subject.module(k)
        case .structure(let k): Subject.structure(k)
        }
    }

    // MARK: 来歴・日誌・ノート

    /// 来歴が指す対象の名前(日誌・仲間の記憶・最後の場面に並べる記録で使う)。
    public func name(of ref: SubjectRef) -> String {
        audited(rawName(of: ref), origin: "ref:\(ref.kindKey)")
    }

    /// 来歴 1 件を日誌の 1 行にする。行為の型(見出し journal:<行為>)が無ければ nil(日誌に出さない)。
    /// 名前は毎回引くので、開示の後に開いた過去の日誌は新しい見え方で読める。
    public func journalLine(_ r: ProvenanceRecord) -> String? {
        let s = Subject.journal(r.act)
        guard let template = variant(s)?.name else { return nil }
        let actor = r.actor.map { rawName(Subject.person($0)) } ?? ""
        let line = rawText(template, ["actor": actor, "subject": rawName(of: r.subject), "count": "\(r.count)"])
        return audited(line, origin: s.rawValue)
    }

    /// ノートの出典のラベル(人・ノアの手・端末…)。R1 は中立の語だけ(BEAT-02)。
    public func source(of entry: NoteEntry) -> String {
        name(entry.source)
    }

    /// ノートの本文。
    public func text(of entry: NoteEntry) -> String {
        text(entry.text)
    }

    // MARK: 地図

    /// 地図の文字(見え方 → 既定の文字の表 → "？")。
    /// 立ち絵(いまの見え方の art。無ければ nil = 枠ごと出さない)。場面の札・仲間のタブで共用。
    public func art(_ s: SubjectID) -> ArtID? { variant(s)?.art }

    public func glyph(_ s: SubjectID) -> String {
        audited(variant(s)?.glyph ?? content.glyphs[s] ?? "？", origin: "glyph \(s.rawValue)")
    }

    /// 地図のラベル(POI・地形・置いた物の名前を長押しで出すときなど)。
    public func mapLabel(_ s: SubjectID) -> String { name(s) }

    // MARK: 数値の見せ方(hidden → 段階の言葉 → 数)

    /// 数値の見せ方(隠れた値は nil)。
    public func stat(_ id: StatID, value: Milli) -> String? {
        guard let display = variant(Subject.stat(id))?.display else { return nil }
        let out: String
        switch display {
        case .hidden:
            return nil
        case .bands(let thresholds, let labels):
            var label = labels.first
            for (i, t) in thresholds.enumerated() where value.raw >= Int64(t) && i + 1 < labels.count { label = labels[i + 1] }
            guard let l = label else { return nil }
            out = rawText(l)
        case .number(let divisor, let unit, let decimals):
            let v = divisor > 0 ? value.raw / Int64(divisor) : value.raw
            out = Self.decimalString(v, places: decimals ?? 0) + (unit.map { rawText($0) } ?? "")
        }
        return audited(out, origin: "stat:\(id.rawValue)")
    }

    /// 整数 v を 10^places で割った値を、小数 places 桁で(切り捨て。浮動小数を使わない)。
    static func decimalString(_ v: Int64, places: Int) -> String {
        guard places > 0 else { return "\(v)" }
        var scale: Int64 = 1
        for _ in 0..<places { scale *= 10 }
        let a = v.magnitude
        let frac = String(a % UInt64(scale))
        return (v < 0 ? "-" : "") + "\(a / UInt64(scale))." + String(repeating: "0", count: places - frac.count) + frac
    }

    // MARK: 書き換わった物

    /// 知っている事実が old から今に変わったとき、見え方が変わり、かつ知らせる(announce)見出し。
    /// 画面の「書き換わった」演出の対象(Frame.renamed)。
    public func renamed(since old: Set<FactID>) -> [SubjectID] {
        let before = Perceiver(content: content, known: old)
        return content.perception.keys.sorted().filter { s in
            guard let now = variantIndex(s), now != before.variantIndex(s) else { return false }
            return content.perception[s]?.variants[now].announce == true
        }
    }

    // MARK: 中身(監査を通さない。外へ返す関数が最後に 1 回だけ監査する)

    func rawName(_ s: SubjectID) -> String {
        rawText(variant(s)?.name ?? Self.unknownText)
    }

    func rawText(_ id: TextID, _ args: [String: String] = [:]) -> String {
        var s = content.texts[id] ?? content.texts[Self.unknownText] ?? "？"
        for (k, v) in args.sorted(by: { $0.key < $1.key }) { s = s.replacingOccurrences(of: "{\(k)}", with: v) }
        return s
    }

    func rawName(of name: MatterName) -> String {
        name.parts.map { part -> String in
            // 無修飾・異常の段で語が空のときは、見え方の name を書かない(空文字列)
            guard let v = variant(Subject.namePart(part)) else { return "" }
            return v.name.map { rawText($0) } ?? ""
        }.joined()
    }

    func rawName(of ref: SubjectRef) -> String {
        switch ref {
        case .matter(let n): rawName(of: n)
        case .choice(let e, let c):
            rawText(content.events[e]?.choices?.first { $0.id == c }?.label ?? Self.unknownText)
        default: rawName(Self.subject(of: ref))
        }
    }

    /// 来歴の対象 → 認識の表の見出し(物質と選択肢は上で別に引く)。
    public static func subject(of ref: SubjectRef) -> SubjectID {
        switch ref {
        case .none: Subject.misc("none")
        case .item(let i): Subject.item(i)
        case .matter: Subject.misc("matter")
        case .entity: Subject.misc("entity")
        case .module(let k, _): Subject.module(k)
        case .structure(let k, _): Subject.structure(k)
        case .person(let p): Subject.person(p)
        case .design: Subject.misc("design")
        case .enemy(let k, _): Subject.enemy(k)
        case .poi(let k, _): Subject.poi(k)
        case .event(let e): Subject.event(e)
        case .choice(let e, _): Subject.event(e)
        case .fact(let f): Subject.fact(f)
        case .research(let r): Subject.research(r)
        case .skill(let s): Subject.skill(s)
        case .interaction(let i): Subject.interaction(i)
        case .part(_, let name): Subject.part(name)
        case .sheet(let s): Subject.sheet(s)
        case .aura(let k, _): Subject.aura(k)
        case .ability(let a): Subject.ability(a)
        }
    }

    private func audited(_ s: String, origin: @autoclosure () -> String) -> String {
        if let a = auditor { a.inspect(s, content: content, known: known, origin: origin()) }
        return s
    }
}

/// 走行中の監査の記録係。Perceiver が外へ返す文字列を全部受け取り、違反だけを貯める。
/// 複数のスレッドから同じ係を使ってよい(中で鍵をかける)。
public final class PerceptionAuditor: @unchecked Sendable {
    private let lock = NSLock()
    private var found: [ForbiddenAudit.Violation] = []
    private var seen = 0
    public let stage: String

    public init(stage: String = "run") { self.stage = stage }

    public func inspect(_ text: String, content: ContentDB, known: Set<FactID>, origin: String) {
        let v = ForbiddenAudit.check(text, content: content, known: known, stage: stage, origin: origin)
        lock.lock()
        seen += 1
        found += v
        lock.unlock()
    }

    /// これまでの違反。
    public var violations: [ForbiddenAudit.Violation] {
        lock.lock()
        defer { lock.unlock() }
        return found
    }

    /// 調べた文字列の数(監査が実際に働いたかをテストで確かめる)。
    public var inspectedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return seen
    }
}
