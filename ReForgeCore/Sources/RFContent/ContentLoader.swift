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
        /// 同じ層の中で同じ ID を 2 回書いた(別のファイルでも)。層をまたぐ置き換えは正しい使い方なのでエラーにしない。
        case duplicate(file: String, keys: [String])
        /// remove に知らない集まりの名前。
        case unknownCollection(file: String, name: String)
        /// 封をした非公開の層を開けない(鍵違い・壊れている・形式が違う)。
        case sealed(String)

        public var description: String {
            switch self {
            case .missingLayer(let p): "コンテンツの層が無い: \(p)"
            case .unknownKeys(let f, let k): "\(f): 知らないキー \(k)"
            case .decode(let f, let m): "\(f): \(m)"
            case .duplicate(let f, let k): "\(f): 同じ層の中で ID が重なっている \(k)"
            case .unknownCollection(let f, let n): "\(f): remove の集まり \(n) を知らない"
            case .sealed(let m): "封をした非公開の層: \(m)"
            }
        }
    }

    /// 非公開の層の場所を指す環境変数。CI と手元の開発で使う(E-content.md §4)。
    public static let privateLayerEnv = "REFORGE_PRIVATE_CONTENT"

    /// 公開の層と(あれば)非公開の層を重ねて読む。
    /// 非公開の層: 環境変数 REFORGE_PRIVATE_CONTENT → 無ければ <公開の層の親>/private(あれば)。どちらも無ければ公開だけ。
    /// 環境変数が指すディレクトリが無いときはエラー(指定の誤記を黙って公開だけにしない)。
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
        return isDirectory(sibling) ? sibling : nil
    }

    /// アプリの束から読む(E-content.md §4.5): <root>/public → <root>/private(平文。手元の開発)があれば重ねる →
    /// 無くて <root>/private.sealed と鍵があれば、開封してメモリ上の層として重ねる(開いた本文はファイルに書かない)。
    /// 鍵違い・壊れた封はエラー(黙って公開だけにしない。アプリは受けて公開だけで起動し、帯に 1 行出す)。
    public static func loadBundled(root: URL, key: Data? = nil) throws -> ContentDB {
        let pub = root.appendingPathComponent("public", isDirectory: true)
        let priv = root.appendingPathComponent("private", isDirectory: true)
        let sealed = root.appendingPathComponent(ContentSeal.fileName)
        if isDirectory(priv) { return try load(layers: [pub, priv]) }
        if let key, FileManager.default.fileExists(atPath: sealed.path) {
            let files = try ContentSeal.open(Data(contentsOf: sealed), key: key)
            return try load(sources: [.directory(pub), .memory(name: "private", files: files)])
        }
        return try load(layers: [pub])
    }

    /// 層の出どころ: ディレクトリか、開封したメモリ上のファイル(層の中の相対パス → 中身)。
    public enum LayerSource: Sendable {
        case directory(URL)
        case memory(name: String, files: [String: Data])
    }

    public static func load(layers: [URL]) throws -> ContentDB {
        try load(sources: layers.map { .directory($0) })
    }

    public static func load(sources: [LayerSource]) throws -> ContentDB {
        var db = ContentDB()
        for source in sources {
            var seen = LayerKeys()
            for (name, data) in try files(of: source) {
                try apply(json: data, to: &db, name: name, seen: &seen)
            }
        }
        return db
    }

    /// 層の中の *.json を(名前, 中身)で、相対パスの昇順に。ディレクトリでもメモリでも同じ順・同じ名前。
    static func files(of source: LayerSource) throws -> [(String, Data)] {
        switch source {
        case .directory(let layer):
            let root = layer.resolvingSymlinksInPath()
            return try relativeJSONPaths(in: layer).map { rel in
                ("\(layer.lastPathComponent)/\(rel)", try Data(contentsOf: root.appendingPathComponent(rel)))
            }
        case .memory(let name, let files):
            return files.keys.filter(isContentPath).sorted().map { ("\(name)/\($0)", files[$0]!) }
        }
    }

    /// 層の中で読むファイルの相対パス(昇順)。封をする側もこれを使う(読むものと封をするものを一致させる)。
    public static func relativeJSONPaths(in layer: URL) throws -> [String] {
        guard isDirectory(layer) else { throw LoadError.missingLayer(layer.path) }
        let root = layer.resolvingSymlinksInPath()
        // 隠しの判定は層の中の相対パスで(層そのものが隠しディレクトリの下にあってもよい)
        return jsonFiles(in: root).map { String($0.resolvingSymlinksInPath().path.dropFirst(root.path.count + 1)) }
            .filter(isContentPath).sorted()
    }

    /// コンテンツとして読む相対パスか: *.json で、隠し(. で始まる)と materials/・tools/・l10n/ の下を除く
    /// (資料と変換スクリプトの置き場に JSON があっても読まない)。
    public static func isContentPath(_ rel: String) -> Bool {
        let parts = rel.split(separator: "/")
        guard rel.hasSuffix(".json"), let first = parts.first else { return false }
        if parts.contains(where: { $0.hasPrefix(".") }) { return false }
        return first != "materials" && first != "tools" && first != "l10n"
    }

    /// 1 つの JSON(テストやツールから)。
    public static func apply(json data: Data, to db: inout ContentDB, name: String = "<memory>") throws {
        var seen = LayerKeys()
        try apply(json: data, to: &db, name: name, seen: &seen)
    }

    static func apply(json data: Data, to db: inout ContentDB, name: String, seen: inout LayerKeys) throws {
        let raw = try checkTopLevelKeys(data, file: name)
        let f: ContentFile
        do {
            f = try JSONDecoder().decode(ContentFile.self, from: data)
        } catch let e as DecodingError {
            throw LoadError.decode(file: name, message: describe(e))
        }
        try checkNestedKeys(raw, decoded: f, file: name)
        try f.apply(to: &db, file: name, seen: &seen)
    }

    static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// 層の中の *.json(隠しファイル・隠しディレクトリ(.git など)は読まない)を相対パスの昇順に。
    static func jsonFiles(in dir: URL) -> [URL] {
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil,
                                                     options: [.skipsHiddenFiles]) else { return [] }
        return e.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "json" }
            .sorted { $0.path < $1.path }
    }

    static func checkTopLevelKeys(_ data: Data, file: String) throws -> [String: Any] {
        let obj: Any
        do {
            obj = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw LoadError.decode(file: file, message: "JSON として読めない")
        }
        guard let dict = obj as? [String: Any] else {
            throw LoadError.decode(file: file, message: "最上位はオブジェクト")
        }
        let unknown = Set(dict.keys).subtracting(ContentFile.CodingKeys.allCases.map(\.rawValue) + [ContentFile.commentKey])
        if !unknown.isEmpty { throw LoadError.unknownKeys(file: file, keys: unknown.sorted()) }
        return dict
    }

    /// 定義の中の知らないキー(項目名の誤記)も見つける。読んだ定義を書き出し直し、元の JSON にあって
    /// 書き出しに無いキーを誤記とみなす(値が null のキーと注記 "//" は除く)。
    static func checkNestedKeys(_ raw: [String: Any], decoded: ContentFile, file: String) throws {
        guard let data = try? JSONEncoder().encode(decoded),
              let enc = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        var unknown: [String] = []
        func walk(_ r: Any, _ e: Any?, _ path: String) {
            if let rd = r as? [String: Any] {
                guard let ed = e as? [String: Any] else { return }
                for (k, v) in rd where k != ContentFile.commentKey && !(v is NSNull) {
                    let p = path.isEmpty ? k : "\(path).\(k)"
                    if let ev = ed[k] { walk(v, ev, p) } else { unknown.append(p) }
                }
            } else if let ra = r as? [Any], let ea = e as? [Any] {
                for (i, v) in ra.enumerated() where i < ea.count { walk(v, ea[i], "\(path)[\(i)]") }
            }
        }
        walk(raw, enc, "")
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

/// 1 つの層の中で書いた鍵(集まり|ID)。同じ層での重なりを見つける。
struct LayerKeys {
    var keys = Set<String>()

    mutating func insert(_ collection: String, _ id: String, dups: inout [String]) {
        if !keys.insert("\(collection)|\(id)").inserted { dups.append("\(collection): \(id)") }
    }
}

/// JSON 1 ファイルの形。どの集まりも省略できる。
struct ContentFile: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case bundle, clock, mapGen, start, rewind, ruleBook, survival, combat, hauling
        case terrains, biomes, pois, handwork, modules, structures, interactions, people, ideologyAxes
        case memoryKinds, lines, hints, research, skills, abilities, enemies, auras, stats, failureRules
        case trackers, facts, events, scenes, sheets, objectives, chapters, endings, findings, documents, groups
        case perception, forbidden, auditStages, textGates, texts, glyphs, latinAllowed, language, nameJoin
        case remove
        // 探索と拠点(U8)
        case fields, exploreEvents, exploration, base
        // 画面の要素の解放(U18)
        case uiGates
        // 図鑑の影の欄(U17)
        case codexShadows
        // 深さの気配(U19)
        case hintThemes, depthHints, mining
    }

    /// 人が読むための注記のキー(読み飛ばす)。
    static let commentKey = "//"

    var bundle: LayerManifest?
    var clock: ClockDef?
    var mapGen: MapGenConfig?
    var start: StartDef?
    var rewind: RewindDef?
    var survival: SurvivalDef?
    var combat: CombatDef?
    var hauling: HaulingDef?
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
    var documents: [DocumentDef]?
    var groups: [GroupDef]?
    var objectives: [ObjectiveDef]?
    var chapters: [ChapterDef]?
    var endings: [EndingDef]?
    var findings: [FindingDef]?
    var perception: [SubjectDef]?
    var forbidden: [ForbiddenRule]?
    var auditStages: [AuditStage]?
    var textGates: [TextGate]?
    var texts: [String: String]?
    /// 無ければ従来どおり日本語の表として読む。
    var language: LanguageID?
    var nameJoin: NameJoin?
    var glyphs: [String: String]?
    /// 画面に出してよいラテン文字の語(足し合わせ)。
    var latinAllowed: [String]?
    /// 前の層の定義を消す(集まりの名前 → ID の並び)。
    var remove: [String: [String]]?
    // 探索と拠点(U8)
    var fields: [FieldDef]?
    var exploreEvents: [ExploreEventDef]?
    var exploration: ExplorationDef?
    var base: BaseDef?
    var uiGates: [UIGateDef]?
    var codexShadows: [CodexShadowDef]?
    var hintThemes: [HintTheme]?
    var depthHints: [DepthHint]?
    var mining: MiningDef?

    func apply(to db: inout ContentDB, file: String, seen: inout LayerKeys) throws {
        let textLanguage = try languageForTexts(file: file)
        if textLanguage == .pseudo {
            throw ContentLoader.LoadError.decode(file: file, message: "x-pseudo は文字列表を持てない")
        }
        if textLanguage != .ja, textGates != nil {
            throw ContentLoader.LoadError.decode(file: file, message: "日本語以外の文字列表に textGates は書けない")
        }
        var dups: [String] = []
        func one(_ name: String, _ present: Bool) { if present { seen.insert(name, "", dups: &dups) } }
        one("bundle", bundle != nil)
        one("clock", clock != nil)
        one("mapGen", mapGen != nil)
        one("start", start != nil)
        one("rewind", rewind != nil)
        one("ruleBook", ruleBook != nil)
        if let b = bundle { db.layers.append(b) }
        if let v = clock { db.clock = v }
        if let v = mapGen { db.mapGen = v }
        if let v = start { db.start = v }
        if let v = rewind { db.rewind = v }
        if let v = survival { db.survival = v }
        if let v = combat { db.combat = v }
        if let v = hauling { db.hauling = v }
        if let v = ruleBook { db.ruleBook = v }
        func upsert<D: ContentDef>(_ name: String, _ dict: inout [D.Key: D], _ items: [D]?) {
            for d in items ?? [] {
                seen.insert(name, "\(d.id)", dups: &dups)
                dict[d.id] = d
            }
        }
        upsert("terrains", &db.terrains, terrains)
        upsert("biomes", &db.biomes, biomes)
        upsert("pois", &db.pois, pois)
        upsert("handwork", &db.handwork, handwork)
        upsert("modules", &db.modules, modules)
        upsert("structures", &db.structures, structures)
        upsert("interactions", &db.interactions, interactions)
        upsert("people", &db.people, people)
        upsert("ideologyAxes", &db.ideologyAxes, ideologyAxes)
        upsert("memoryKinds", &db.memoryKinds, memoryKinds)
        upsert("lines", &db.lines, lines)
        upsert("hints", &db.hints, hints)
        upsert("research", &db.research, research)
        upsert("skills", &db.skills, skills)
        upsert("abilities", &db.abilities, abilities)
        upsert("enemies", &db.enemies, enemies)
        upsert("auras", &db.auras, auras)
        upsert("stats", &db.stats, stats)
        upsert("failureRules", &db.failureRules, failureRules)
        upsert("trackers", &db.trackers, trackers)
        upsert("facts", &db.facts, facts)
        upsert("events", &db.events, events)
        upsert("scenes", &db.scenes, scenes)
        upsert("sheets", &db.sheets, sheets)
        upsert("documents", &db.documents, documents)
        upsert("groups", &db.groups, groups)
        upsert("objectives", &db.objectives, objectives)
        upsert("chapters", &db.chapters, chapters)
        upsert("endings", &db.endings, endings)
        upsert("findings", &db.findings, findings)
        upsert("perception", &db.perception, perception)
        // 禁止語の規則は層をまたいで足し合わせる(公開の試験用の語 + 非公開の本物)
        db.forbidden += forbidden ?? []
        for s in auditStages ?? [] {
            seen.insert("auditStages", s.id, dups: &dups)
            if let i = db.auditStages.firstIndex(where: { $0.id == s.id }) { db.auditStages[i] = s } else { db.auditStages.append(s) }
        }
        for g in textGates ?? [] {
            seen.insert("textGates", g.text.rawValue, dups: &dups)
            db.textGates[g.text] = g
        }
        if let nameJoin { db.textTables.meta[textLanguage] = TextMeta(nameJoin: nameJoin) }
        var textTable = db.textTables.tables[textLanguage] ?? [:]
        for (k, v) in texts ?? [:] {
            seen.insert("texts.\(textLanguage.rawValue)", k, dups: &dups)
            textTable[TextID(k)] = v
        }
        if texts != nil { db.textTables.tables[textLanguage] = textTable }
        for (k, v) in glyphs ?? [:] {
            seen.insert("glyphs", k, dups: &dups)
            db.glyphs[SubjectID(k)] = v
        }
        for w in latinAllowed ?? [] {
            seen.insert("latinAllowed", w, dups: &dups)
            if !db.latinAllowed.contains(w) { db.latinAllowed.append(w) }
        }
        // 探索と拠点(U8)
        upsert("fields", &db.fields, fields)
        upsert("exploreEvents", &db.exploreEvents, exploreEvents)
        if let v = exploration { db.exploration = v }
        if let v = base { db.base = v }
        upsert("uiGates", &db.uiGates, uiGates)
        upsert("codexShadows", &db.codexShadows, codexShadows)
        upsert("hintThemes", &db.hintThemes, hintThemes)
        upsert("depthHints", &db.depthHints, depthHints)
        if let v = mining { db.mining = v }
        if !dups.isEmpty { throw ContentLoader.LoadError.duplicate(file: file, keys: dups.sorted()) }
        for (collection, ids) in (remove ?? [:]).sorted(by: { $0.key < $1.key }) {
            guard Self.remove(collection, ids, from: &db) else {
                throw ContentLoader.LoadError.unknownCollection(file: file, name: collection)
            }
        }
    }

    /// 前の層の定義を消す。知らない集まりの名前なら false。
    private static func remove(_ collection: String, _ ids: [String], from db: inout ContentDB) -> Bool {
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
        case "ideologyAxes": drop(&db.ideologyAxes)
        case "memoryKinds": drop(&db.memoryKinds)
        case "lines": drop(&db.lines)
        case "hints": drop(&db.hints)
        case "research": drop(&db.research)
        case "skills": drop(&db.skills)
        case "abilities": drop(&db.abilities)
        case "enemies": drop(&db.enemies)
        case "auras": drop(&db.auras)
        case "stats": drop(&db.stats)
        case "failureRules": drop(&db.failureRules)
        case "trackers": drop(&db.trackers)
        case "facts": drop(&db.facts)
        case "events": drop(&db.events)
        case "scenes": drop(&db.scenes)
        case "sheets": drop(&db.sheets)
        case "documents": drop(&db.documents)
        case "groups": drop(&db.groups)
        case "objectives": drop(&db.objectives)
        case "chapters": drop(&db.chapters)
        case "endings": drop(&db.endings)
        case "findings": drop(&db.findings)
        case "perception": drop(&db.perception)
        case "textGates": drop(&db.textGates)
        case "texts":
            for language in Array(db.textTables.tables.keys) {
                for id in ids { db.textTables.tables[language]?[TextID(id)] = nil }
            }
        case "fields": drop(&db.fields)
        case "exploreEvents": drop(&db.exploreEvents)
        case "hintThemes": drop(&db.hintThemes)
        case "depthHints": for id in ids { db.depthHints[id] = nil }
        case "uiGates": drop(&db.uiGates)
        case "codexShadows": drop(&db.codexShadows)
        case "glyphs": drop(&db.glyphs)
        case "auditStages": db.auditStages.removeAll { ids.contains($0.id) }
        case "latinAllowed": db.latinAllowed.removeAll { ids.contains($0) }
        // 禁止語の規則は名札(id)で消す(名札の無い規則は消せない)
        case "forbidden": db.forbidden.removeAll { $0.id.map(ids.contains) ?? false }
        default: return false
        }
        return true
    }

    /// text/<language>/ に置いた表は、ファイルの language と食い違わせない。
    private func languageForTexts(file: String) throws -> LanguageID {
        let result = language ?? .ja
        let parts = file.split(separator: "/").map(String.init)
        guard let textIndex = parts.lastIndex(of: "text"), textIndex + 1 < parts.count,
              let pathLanguage = LanguageID(rawValue: parts[textIndex + 1]) else
        {
            return result
        }
        guard pathLanguage == result else {
            throw ContentLoader.LoadError.decode(file: file, message: "text の置き場所と言語が違う")
        }
        return result
    }
}
