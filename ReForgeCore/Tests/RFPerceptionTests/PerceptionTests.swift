import Foundation
import RFContent
import RFKernel
import RFMatter
import RFPerception
import RFPresent
import RFRules
import RFSim
import RFTestSupport
import RFWorld
import XCTest

final class PerceptionTests: XCTestCase {
    // MARK: 遡る書き換え(TEST-S4 / REQ-S7)

    /// 事実を知る前に作った物・置いた物・図鑑・ノートの出典・地図のラベル・過去の日誌が、知った瞬間に
    /// 新しい見え方で描かれる。保存されているデータは同じ ID のまま(名前を保存していない)。
    func testFactRewritesEveryPastRecordRetroactively() throws {
        let rig = try TestRig.publicOnly()
        var ctx = StepContext(world: rig.factory.newWorld(seed: 1), content: rig.content)
        // 置いた炉
        let furnace = ctx.world.newEntityID()
        let placed = ctx.record(.placed, .module("furnace", furnace), actor: .noah)
        ctx.world.placements.items[furnace] = Placement(id: furnace, kind: .module("furnace"), at: ctx.world.map.spawn,
                                                        facing: .north, origin: placed, status: .running)
        // 作った鉄の板(在庫と図鑑)
        let iron = Matter(substance: .iron, purity: Purity(percent: 90), stage: .metal, shape: .plate, temper: .hard)
        let ironName = NameGenerator.name(for: iron)
        let crafted = ctx.record(.crafted, .matter(ironName), actor: .noah, inputs: [placed])
        ctx.addStock(.matter(iron), 2, to: .base, origin: crafted)
        ctx.world.notebook.codex.append(CodexEntry(name: ironName, bestPurity: iron.purity, firstSeen: crafted))
        // 中立の出典つきの書き留め(BEAT-02)
        ctx.world.notebook.notes.append(NoteEntry(about: Subject.item("test_ore"), text: "text.test.note",
                                                  source: Subject.source("test.hand"), record: crafted,
                                                  at: ctx.world.clock.now, run: ctx.world.run.index))
        // 仲間が残骸を漁った(地図のラベル・日誌)
        _ = ctx.record(.scavenged, .poi("poi.test.wreck", nil), actor: "person.test_a")
        let world = ctx.world

        func render(_ w: WorldState) -> [String: String] {
            let p = Perceiver(content: rig.content, world: w)
            var out: [String: String] = [:]
            for (i, s) in (w.inventory.holders[.base] ?? []).enumerated() { out["stock\(i)"] = p.name(of: s.stuff) }
            out["placed"] = p.name(of: w.placements.items[furnace]!.kind)
            out["codex"] = p.name(of: w.notebook.codex[0].name)
            out["source"] = p.source(of: w.notebook.notes[0])
            out["map"] = p.mapLabel(Subject.poi("poi.test.wreck"))
            for r in w.ledger.records { if let l = p.journalLine(r) { out["journal\(r.id.raw)"] = l } }
            return out
        }
        let before = render(world)
        XCTAssertTrue(before.values.contains("見慣れない石"), "\(before)")
        XCTAssertEqual(before["placed"], "炉")
        XCTAssertEqual(before["source"], "手の覚え")
        XCTAssertEqual(before["map"], "試験の残骸")
        XCTAssertEqual(before["journal\(placed.raw)"], "ノアが炉を置いた")
        XCTAssertTrue(before.values.contains("試験の仲間Aが試験の残骸を漁った"), "\(before)")

        var learn = StepContext(world: world, content: rig.content)
        learn.learn("fact.test.revealed")
        XCTAssertTrue(learn.changes.areas.contains(.perception), "見え方を引き直す印が付く")
        let after = render(learn.world)
        XCTAssertTrue(after.values.contains("禁句Aの石"), "\(after)")
        XCTAssertEqual(after["placed"], "本当の炉")
        XCTAssertTrue(after["codex"]!.contains("本当の鉄") && !before["codex"]!.contains("本当の鉄"), "\(after)")
        XCTAssertEqual(after["source"], "試験の出典")
        XCTAssertEqual(after["map"], "本当の残骸")
        XCTAssertEqual(after["journal\(placed.raw)"], "ノアが本当の炉を置いた")
        XCTAssertTrue(after.values.contains("試験の仲間Aが本当の残骸を漁った"), "\(after)")

        // 保存されている物・置いた物・ノート・地図は同じ ID のまま。保存データに名前は入っていない
        XCTAssertEqual(learn.world.inventory, world.inventory)
        XCTAssertEqual(learn.world.placements, world.placements)
        XCTAssertEqual(learn.world.notebook, world.notebook)
        XCTAssertEqual(learn.world.map, world.map)
        let json = String(decoding: try JSONEncoder().encode(learn.world), as: UTF8.self)
        for s in Set(before.values).union(after.values) { XCTAssertFalse(json.contains(s), "保存データに名前「\(s)」") }

        // 書き換わったことを知らせる見出し(announce)
        let renamed = Perceiver(content: rig.content, world: learn.world).renamed(since: world.knowledge.factSet)
        XCTAssertEqual(Set(renamed), ["item:test_ore", "substance:Fe", "poi:poi.test.wreck"])
    }

    /// 数値の見せ方も事実で切り替わる(段階の言葉 → 数)。隠れた値は出さない。
    func testStatDisplaySwitchesAndHiddenStaysHidden() throws {
        let db = try TestContent.publicOnly()
        XCTAssertEqual(Perceiver(content: db, known: []).stat("stat.test.air", value: Milli(raw: 950)), "濁っている")
        XCTAssertEqual(Perceiver(content: db, known: []).stat("stat.test.air", value: Milli(raw: 100)), "澄んでいる")
        XCTAssertEqual(Perceiver(content: db, known: ["fact.test.revealed"]).stat("stat.test.air", value: Milli(raw: 950)), "95")
        XCTAssertNil(Perceiver(content: db, known: []).stat("stat.test.hidden", value: Milli(raw: 5)))
        XCTAssertNil(Perceiver(content: db, known: []).stat("stat.no_such", value: Milli(raw: 5)))
    }

    /// 数の見せ方の小数の桁(整数の計算・切り捨て)。decimals を省いた JSON も読める。
    func testStatNumberWithDecimals() throws {
        var db = try TestContent.publicOnly()
        try ContentLoader.apply(json: Data(#"""
        {"perception": [{"subject": "stat:stat.test.air", "variants": [
          {"when": true, "name": "text.stat.air", "display": {"number": {"divisor": 10, "unit": "text.test.percent", "decimals": 2}}}]}],
         "texts": {"text.test.percent": "%"}}
        """#.utf8), to: &db)
        let p = Perceiver(content: db, known: [])
        XCTAssertEqual(p.stat("stat.test.air", value: Milli(raw: 800)), "0.80%")
        XCTAssertEqual(p.stat("stat.test.air", value: Milli(raw: 805)), "0.80%", "切り捨て")
        XCTAssertEqual(p.stat("stat.test.air", value: Milli(raw: 12345)), "12.34%")
        XCTAssertEqual(p.stat("stat.test.air", value: Milli(raw: -50)), "-0.05%")
        XCTAssertEqual(ContentValidator.validate(db).filter { $0.level == .error }, [])
        db.perception["stat:stat.test.air"]?.variants[0].display = .number(divisor: 10, unit: nil, decimals: 9)
        XCTAssertTrue(ContentValidator.validate(db).contains { $0.rule == "perception.number" })
    }

    /// 物質の名前は部品ごとに引いて連結する。
    func testMatterNameFromParts() throws {
        let db = try TestContent.publicOnly()
        let m = Matter(substance: .iron, purity: Purity(percent: 90), stage: .metal, shape: .plate, temper: .hard)
        let name = Perceiver(content: db, known: []).name(of: .matter(m))
        XCTAssertTrue(name.contains("鉄") && name.contains("板") && name.contains("精"), name)
    }

    /// 見え方の無い見出し・文字列表に無いキー・日誌の型の無い行為は、英語の ID を出さない。
    func testUnknownSubjectNeverLeaksID() throws {
        let p = Perceiver(content: try TestContent.publicOnly(), known: [])
        XCTAssertEqual(p.name("item:no_such_thing"), "？")
        XCTAssertEqual(p.text("text.no_such_key"), "？")
        XCTAssertEqual(p.glyph("terrain:no_such"), "？")
        XCTAssertEqual(p.name(of: SubjectRef.entity(EntityID(3))), "？")
        let r = ProvenanceRecord(id: ProvenanceID(1), at: GameTime(seconds: 0), day: 1, run: 0, actor: .noah,
                                 act: .overridden, subject: .none)
        XCTAssertNil(p.journalLine(r), "型の無い行為は日誌に出さない")
    }

    // MARK: 走行中の監査

    /// 監査つきの Perceiver は、外へ返した文字列を全部調べ、まだ知らない事実の語を捕まえる。
    func testAuditingPerceiverCatchesLeak() throws {
        let db = try TestContent.publicOnly()
        let a = PerceptionAuditor()
        let p = Perceiver(content: db, known: [], auditor: a)
        XCTAssertEqual(p.name(Subject.item("test_ore")), "見慣れない石")
        _ = p.name(of: .item("wood"))
        _ = p.glyph(Subject.terrain("grass"))
        XCTAssertEqual(a.violations, [])
        XCTAssertEqual(a.inspectedCount, 3)
        // 開示の前に真実の見え方の文字列を直接出してしまう(漏れ)
        _ = p.text("text.item.test_ore.true")
        XCTAssertEqual(a.violations.map(\.rule), ["rule.test.a"])
        // 開示の後なら同じ文字列は違反でない
        let b = PerceptionAuditor()
        _ = Perceiver(content: db, known: ["fact.test.revealed"], auditor: b).text("text.item.test_ore.true")
        XCTAssertEqual(b.violations, [])
    }

    /// 走行中の監査(ボット走行の形): 昼を進め、開示の前後で Frame・地図の全マス・日誌・在庫・ノートの文字列が 0 件。
    func testRuntimeAuditOverPlayedDay() throws {
        let rig = try TestRig.publicOnly()
        var w = rig.factory.newWorld(seed: 7)
        let fb = FrameBuilder(content: rig.content)
        var frame: Frame?
        var revision = 0
        var checked = 0

        func auditNow(_ report: StepReport?) {
            revision += 1
            let f = fb.build(w, revision: revision, previous: frame, report: report)
            frame = f
            let a = PerceptionAuditor()
            let p = Perceiver(content: rig.content, world: w, auditor: a)
            var strings = Self.strings(of: f)
            let size = f.map.size
            for y in 0..<size.height {
                for x in 0..<size.width { strings.append(fb.tile(w, at: GridPoint(x, y)).glyph) }
            }
            for r in w.ledger.records { _ = p.journalLine(r) }
            for (_, list) in w.inventory.holders { for s in list { _ = p.name(of: s.stuff) } }
            for n in w.notebook.notes { _ = p.source(of: n); _ = p.text(of: n) }
            let v = ForbiddenAudit.check(strings, content: rig.content, known: w.knowledge.factSet) + a.violations
            XCTAssertEqual(v, [], "\(v.prefix(5))")
            checked += strings.count + a.inspectedCount
        }

        auditNow(nil)
        auditNow(rig.playDay(&w))
        var ctx = StepContext(world: w, content: rig.content)
        ctx.learn("fact.test.revealed")
        w = ctx.world
        var report = StepReport()
        report.changes = ctx.changes
        auditNow(report)
        XCTAssertGreaterThan(checked, 1000, "監査が実際に文字列を見ている")
    }

    static func strings(of f: Frame) -> [String] {
        var s: [String] = []
        s += f.status.flatMap { [$0.label, $0.value] }
        s += f.actors.flatMap { [$0.label, $0.glyph] }
        s += f.placements.flatMap { [$0.glyph] + [$0.stoppedReason, $0.throughput].compactMap { $0 } }
        s += f.decision?.choices.map(\.label) ?? []
        s += f.sceneLines + f.notices + f.renamed
        return s
    }

    // MARK: 静的な監査

    /// 静的な監査: 公開の試験用コンテンツは全段(手で書いた段 + 規則ごとの自動の段)で 0 件。
    func testPublicContentPassesAudit() throws {
        XCTAssertEqual(ForbiddenAudit.audit(try TestContent.publicOnly()), [])
    }

    /// 非公開の層があれば、重ねたコンテンツも全段で 0 件(無ければ公開だけでもう一度)。
    func testFullContentPassesAudit() throws {
        let v = ForbiddenAudit.audit(try TestContent.full())
        XCTAssertEqual(v.count, 0, "\(v.prefix(20))")
    }

    /// 監査は、まだ知らない事実の語と英語の ID を捕まえる(走行中の検査の関数)。
    func testRuntimeCheckCatchesForbiddenWordAndEnglishID() throws {
        let db = try TestContent.publicOnly()
        XCTAssertEqual(ForbiddenAudit.check("禁句Aの石", content: db, known: []).count, 1)
        XCTAssertEqual(ForbiddenAudit.check("禁句Aの石", content: db, known: ["fact.test.revealed"]).count, 0)
        XCTAssertEqual(ForbiddenAudit.check("iron_ore", content: db, known: []).map(\.rule), [ForbiddenAudit.latinRule])
        XCTAssertEqual(ForbiddenAudit.check("fact.test", content: db, known: []).count, 1)
        XCTAssertEqual(ForbiddenAudit.check("A_B", content: db, known: []).count, 1, "アンダーバー付きの識別子")
        // 文の型の埋め込み {名前} は ID ではない
        XCTAssertEqual(ForbiddenAudit.check("{actor}が{subject}を置いた", content: db, known: []), [])
    }

    /// 許すラテン文字の語(固有名・題名)は英語の ID とみなさない。それ以外の ID は引き続き捕まえる。
    func testLatinAllowedWordsAreNotInternalIDs() throws {
        var db = try TestContent.publicOnly()
        XCTAssertEqual(ForbiddenAudit.check("Re:Forgeの朝", content: db, known: []).map(\.rule), [ForbiddenAudit.latinRule])
        try ContentLoader.apply(json: Data(#"{"latinAllowed": ["Re:Forge"]}"#.utf8), to: &db)
        XCTAssertEqual(ForbiddenAudit.check("Re:Forgeの朝", content: db, known: []), [])
        XCTAssertEqual(ForbiddenAudit.check("Re:Forgeとiron_ore", content: db, known: []).count, 1)
        XCTAssertEqual(ForbiddenAudit.check("Re:Forgedの朝", content: db, known: []).count, 1, "許した語の続きは別の語")
        XCTAssertEqual(ContentValidator.validate(db).filter { $0.rule == "latinAllowed.id" }, [])
        db.latinAllowed += ["iron_ore", "fact.x"]
        XCTAssertEqual(ContentValidator.validate(db).filter { $0.rule == "latinAllowed.id" }.count, 2)
    }

    /// 手で書いた段に無い事実の組み合わせでも、規則が解ける前に出うる漏れを自動の段が捕まえる。
    func testDerivedStageCatchesLeakNotCoveredByWrittenStages() throws {
        var db = try TestContent.publicOnly()
        // alpha を知ると(revealed より前でも)真実の語が出てしまう見え方
        db.perception["item:wood"] = SubjectDef(subject: "item:wood", variants: [
            Variant(when: .fact("fact.test.alpha"), name: "text.test.leak"), Variant(when: .always, name: "text.item.wood"),
        ])
        db.texts["text.test.leak"] = "禁句Aの薪"
        // 書いた段(何も知らない / 全部知った)だけでは見つからない
        XCTAssertFalse(db.auditStages.contains { Set($0.facts).contains("fact.test.alpha") && !Set($0.facts).contains("fact.test.revealed") })
        let v = ForbiddenAudit.audit(db)
        XCTAssertEqual(v.map(\.rule), ["rule.test.a"])
        XCTAssertEqual(v.first?.stage, "until:rule.test.a")
        XCTAssertTrue(v.first?.origin.hasPrefix("item:wood") ?? false)
        // 段を手で書く規則(strict = false)なら、自動の段は作らない
        db.forbidden[0].strict = false
        XCTAssertEqual(ForbiddenAudit.audit(db), [])
    }

    /// 門(textGates)の付いた文字列は門が開く段だけで、門の無い文字列はいつでも出うるとして調べる。
    func testGatedAndUngatedTexts() throws {
        var db = try TestContent.publicOnly()
        db.texts["text.test.gated"] = "禁句Aが見える"
        db.textGates["text.test.gated"] = TextGate(text: "text.test.gated", gate: .fact("fact.test.revealed"))
        XCTAssertEqual(ForbiddenAudit.audit(db), [], "開示の後にだけ出る文字列は違反でない")
        db.textGates["text.test.gated"] = TextGate(text: "text.test.gated", gate: .fact("fact.test.alpha"))
        XCTAssertFalse(ForbiddenAudit.audit(db).isEmpty, "開示の前に門が開く")
        db.textGates["text.test.gated"] = nil
        XCTAssertFalse(ForbiddenAudit.audit(db).isEmpty, "門が無ければいつでも出うる")
    }

    /// ノートの出典のラベルも監査の対象(R1 は中立の語だけ。BEAT-02 / REQ-S5 / TEST-S3)。
    func testNoteSourceLabelIsAudited() throws {
        var db = try TestContent.publicOnly()
        db.perception["source:test.hand"] = SubjectDef(subject: "source:test.hand", variants: [
            Variant(when: .always, name: "text.test.badsource"),
        ])
        db.texts["text.test.badsource"] = "禁句Aの手"
        let v = ForbiddenAudit.audit(db)
        XCTAssertFalse(v.isEmpty)
        XCTAssertTrue(v.allSatisfy { $0.origin.hasPrefix("source:test.hand") }, "\(v)")
    }

    /// 違反の表示は既定で語と文を伏せる(公開の CI のログに禁止語を出さない)。
    func testViolationDescriptionHidesWordsByDefault() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment[ForbiddenAudit.verboseEnv] == "1")
        let db = try TestContent.publicOnly()
        let v = try XCTUnwrap(ForbiddenAudit.check("禁句Aの石", content: db, known: [], origin: "x").first)
        XCTAssertFalse(v.description.contains("禁句A"), v.description)
        XCTAssertTrue(v.description.contains("rule.test.a"), v.description)
    }

    /// アプリの画面の固定文言(Localizable.xcstrings)も、重ねたコンテンツの規則で全段 0 件。
    func testAppStringCatalogPassesRules() throws {
        let url = TestContent.repoRoot.appendingPathComponent("ReForge/Resources/Localizable.xcstrings")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path), "アプリの文字列カタログが無い")
        let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let keys = try XCTUnwrap(obj?["strings"] as? [String: Any]).keys.sorted()
        XCTAssertFalse(keys.isEmpty)
        let v = ForbiddenAudit.auditFixedStrings(keys, content: try TestContent.full(), origin: "Localizable.xcstrings")
        XCTAssertEqual(v.count, 0, "\(v.prefix(20))")
    }
}
