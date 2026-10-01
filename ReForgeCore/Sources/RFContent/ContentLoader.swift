import Foundation
import RFKernel
import RFMap
import RFMatter

/// コンテンツの層(ディレクトリ)を順に重ねて ContentDB を作る(E-content.md §3)。
///
/// - 層 = ディレクトリ 1 つ。中の *.json を相対パスの昇順に全部読む(どのファイルにどの集まりを書いてもよい)。
/// - 層は public → private の順に重ねる。同じ ID は後の層が丸ごと置き換える。"remove" で消せる。
/// - 知らない最上位のキーは誤記としてエラーにする(黙って読み飛ばさない)。
public enum ContentLoader {
    public enum LoadError: Error, Equatable, CustomStringConvertible {
        case missingLayer(String)
        case unknownKeys(file: String, keys: [String])
        case decode(file: String, message: String)

        public var description: String {
            switch self {
            case .missingLayer(let p): "コンテンツの層が無い: \(p)"
            case .unknownKeys(let f, let k): "\(f): 知らないキー \(k)"
            case .decode(let f, let m): "\(f): \(m)"
            }
        }
    }

    /// 非公開の層の場所を指す環境変数。CI と手元の開発で使う(E-content.md §4)。
    public static let privateLayerEnv = "REFORGE_PRIVATE_CONTENT"

    /// 公開の層と(あれば)非公開の層を重ねて読む。
    /// 非公開の層: 環境変数 REFORGE_PRIVATE_CONTENT → 無ければ <公開の層の親>/private(あれば)。
    public static func loadDefault(publicLayer: URL, environment: [String: String] = ProcessInfo.processInfo.environment)
        throws -> ContentDB
    {
        var layers = [publicLayer]
        if let p = privateLayer(publicLayer: publicLayer, environment: environment) { layers.append(p) }
        return try load(layers: layers)
    }

    public static func privateLayer(publicLayer: URL, environment: [String: String]) -> URL? {
        if let env = environment[privateLayerEnv], !env.isEmpty {
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        let sibling = publicLayer.deletingLastPathComponent().appendingPathComponent("private", isDirectory: true)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: sibling.path, isDirectory: &isDir), isDir.boolValue {
            return sibling
        }
        return nil
    }

    public static func load(layers: [URL]) throws -> ContentDB {
        var db = ContentDB()
        for layer in layers {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: layer.path, isDirectory: &isDir), isDir.boolValue else {
                throw LoadError.missingLayer(layer.path)
            }
            for file in jsonFiles(in: layer) {
                let data = try Data(contentsOf: file)
                let name = file.path.replacingOccurrences(of: layer.path, with: layer.lastPathComponent)
                try checkKeys(data, file: name)
                do {
                    let f = try JSONDecoder().decode(ContentFile.self, from: data)
                    f.apply(to: &db)
                } catch let e as DecodingError {
                    throw LoadError.decode(file: name, message: describe(e))
                }
            }
        }
        return db
    }

    /// 1 つの JSON(テストやツールから)。
    public static func apply(json data: Data, to db: inout ContentDB, name: String = "<memory>") throws {
        try checkKeys(data, file: name)
        do {
            try JSONDecoder().decode(ContentFile.self, from: data).apply(to: &db)
        } catch let e as DecodingError {
            throw LoadError.decode(file: name, message: describe(e))
        }
    }

    static func jsonFiles(in dir: URL) -> [URL] {
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return e.compactMap { $0 as? URL }.filter { $0.pathExtension == "json" }
            .sorted { $0.path < $1.path }
    }

    static func checkKeys(_ data: Data, file: String) throws {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LoadError.decode(file: file, message: "最上位はオブジェクト")
        }
        let unknown = Set(obj.keys).subtracting(ContentFile.CodingKeys.allCases.map(\.rawValue) + [ContentFile.commentKey])
        if !unknown.isEmpty { throw LoadError.unknownKeys(file: file, keys: unknown.sorted()) }
    }

    static func describe(_ e: DecodingError) -> String {
        switch e {
        case .keyNotFound(let k, let c): "キー \(k.stringValue) が無い(\(path(c)))"
        case .typeMismatch(_, let c), .valueNotFound(_, let c), .dataCorrupted(let c):
            "\(c.debugDescription)(\(path(c)))"
        @unknown default: "\(e)"
        }
    }

    static func path(_ c: DecodingError.Context) -> String {
        c.codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
    }
}

/// JSON 1 ファイルの形。どの集まりも省略できる。
struct ContentFile: Decodable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case bundle, clock, mapGen, start, rewind, ruleBook, survival
        case terrains, biomes, pois, handwork, modules, structures, interactions, people, ideologyAxes
        case memoryKinds, lines, hints, research, skills, abilities, enemies, auras, stats, failureRules
        case trackers, facts, events, scenes, sheets, objectives, chapters, endings, findings
        case perception, forbidden, auditStages, textGates, texts, glyphs
        case remove
        // 探索と拠点(U8)
        case fields, exploreEvents, exploration, base
    }

    /// 人が読むための注記のキー(読み飛ばす)。
    static let commentKey = "//"

    var bundle: LayerManifest?
    var clock: ClockDef?
    var mapGen: MapGenConfig?
    var start: StartDef?
    var rewind: RewindDef?
    var survival: SurvivalDef?
    var ruleBook: RuleBook?
    var terrains: [TerrainDef]?
    var biomes: [BiomeDef]?
    var pois: [POIDef]?
    var handwork: [HandworkDef]?
    var modules: [ModuleDef]?
    var structures: [StructureDef]?
    var interactions: [InteractionDef]?
    var people: [PersonDef]?
    var ideologyAxes: [IdeologyAxisDef]?
    var memoryKinds: [MemoryKindDef]?
    var lines: [LineDef]?
    var hints: [HintDef]?
    var research: [ResearchDef]?
    var skills: [SkillDef]?
    var abilities: [AbilityDef]?
    var enemies: [EnemyDef]?
    var auras: [AuraDef]?
    var stats: [StatDef]?
    var failureRules: [FailureRuleDef]?
    var trackers: [TrackerDef]?
    var facts: [FactDef]?
    var events: [EventDef]?
    var scenes: [SceneDef]?
    var sheets: [SheetDef]?
    var objectives: [ObjectiveDef]?
    var chapters: [ChapterDef]?
    var endings: [EndingDef]?
    var findings: [FindingDef]?
    var perception: [SubjectDef]?
    var forbidden: [ForbiddenRule]?
    var auditStages: [AuditStage]?
    var textGates: [TextGate]?
    var texts: [String: String]?
    var glyphs: [String: String]?
    /// 前の層の定義を消す(集まりの名前 → ID の並び)。
    var remove: [String: [String]]?
    // 探索と拠点(U8)
    var fields: [FieldDef]?
    var exploreEvents: [ExploreEventDef]?
    var exploration: ExplorationDef?
    var base: BaseDef?

    func apply(to db: inout ContentDB) {
        if let b = bundle { db.layers.append(b) }
        if let v = clock { db.clock = v }
        if let v = mapGen { db.mapGen = v }
        if let v = start { db.start = v }
        if let v = rewind { db.rewind = v }
        if let v = survival { db.survival = v }
        if let v = ruleBook { db.ruleBook = v }
        upsert(&db.terrains, terrains)
        upsert(&db.biomes, biomes)
        upsert(&db.pois, pois)
        upsert(&db.handwork, handwork)
        upsert(&db.modules, modules)
        upsert(&db.structures, structures)
        upsert(&db.interactions, interactions)
        upsert(&db.people, people)
        upsert(&db.ideologyAxes, ideologyAxes)
        upsert(&db.memoryKinds, memoryKinds)
        upsert(&db.lines, lines)
        upsert(&db.hints, hints)
        upsert(&db.research, research)
        upsert(&db.skills, skills)
        upsert(&db.abilities, abilities)
        upsert(&db.enemies, enemies)
        upsert(&db.auras, auras)
        upsert(&db.stats, stats)
        upsert(&db.failureRules, failureRules)
        upsert(&db.trackers, trackers)
        upsert(&db.facts, facts)
        upsert(&db.events, events)
        upsert(&db.scenes, scenes)
        upsert(&db.sheets, sheets)
        upsert(&db.objectives, objectives)
        upsert(&db.chapters, chapters)
        upsert(&db.endings, endings)
        upsert(&db.findings, findings)
        upsert(&db.perception, perception)
        db.forbidden += forbidden ?? []
        for s in auditStages ?? [] {
            if let i = db.auditStages.firstIndex(where: { $0.id == s.id }) { db.auditStages[i] = s } else { db.auditStages.append(s) }
        }
        for g in textGates ?? [] { db.textGates[g.text] = g }
        for (k, v) in texts ?? [:] { db.texts[TextID(k)] = v }
        for (k, v) in glyphs ?? [:] { db.glyphs[SubjectID(k)] = v }
        // 探索と拠点(U8)
        upsert(&db.fields, fields)
        upsert(&db.exploreEvents, exploreEvents)
        if let v = exploration { db.exploration = v }
        if let v = base { db.base = v }
        for (collection, ids) in remove ?? [:] { Self.remove(collection, ids, from: &db) }
    }

    private func upsert<D: ContentDef>(_ dict: inout [D.Key: D], _ items: [D]?) {
        for d in items ?? [] { dict[d.id] = d }
    }

    private static func remove(_ collection: String, _ ids: [String], from db: inout ContentDB) {
        func drop<K: RawRepresentable & Hashable, V>(_ d: inout [K: V]) where K.RawValue == String {
            for id in ids { if let k = K(rawValue: id) { d[k] = nil } }
        }
        switch collection {
        case "terrains": drop(&db.terrains)
        case "biomes": drop(&db.biomes)
        case "pois": drop(&db.pois)
        case "handwork": drop(&db.handwork)
        case "modules": drop(&db.modules)
        case "structures": drop(&db.structures)
        case "interactions": drop(&db.interactions)
        case "people": drop(&db.people)
        case "lines": drop(&db.lines)
        case "hints": drop(&db.hints)
        case "research": drop(&db.research)
        case "skills": drop(&db.skills)
        case "enemies": drop(&db.enemies)
        case "auras": drop(&db.auras)
        case "facts": drop(&db.facts)
        case "events": drop(&db.events)
        case "scenes": drop(&db.scenes)
        case "sheets": drop(&db.sheets)
        case "objectives": drop(&db.objectives)
        case "perception": drop(&db.perception)
        case "texts": drop(&db.texts)
        case "fields": drop(&db.fields)
        case "exploreEvents": drop(&db.exploreEvents)
        default: break
        }
    }
}
