import Foundation

/// Temporary names accepted while the private content layer is migrated.
/// Remove this entire file after that migration is complete.
public enum LegacyNames {
    private static let exact: [String: String] = [
        "manifest": "roster",
        "aboard": "included",
        "staying": "excluded",
        "imprint": "grant",
        "imprinted": "granted",
        "setBoarding": "setRosterPick",
        "lockManifest": "confirmRoster",
        "boardingDeclared": "rosterDeclared",
        "manifestLocked": "rosterConfirmed",
        "imprintDeclined": "grantDeclined",
        "boarding.declared": "roster.declared",
        "manifest.locked": "roster.confirmed",
        "boarding.aboard": "roster.include",
        "boarding.stay": "roster.exclude",
        "imprint.declined": "grant.declined",
        "imprint.refuse": "grant.refuse",
        "reason.manifest.locked": "reason.roster.confirmed",
        // 公開の層の試験用の ID(非公開の層の remove が今も古い ID を挙げている)
        "sheet.test.manifest": "sheet.test.roster",
        "sheet:sheet.test.manifest": "sheet:sheet.test.roster",
        "text.test.sheet_manifest": "text.test.sheet_roster",
        "fact.test.vessel_ready": "fact.test.roster_open",
        "memory.test.gap": "memory.test.kind_b",
        "event.test.gap_seen": "event.test.memory_seen",
        "text.item.test_ore.true": "text.item.test_ore.variant_b",
        "text.module.furnace.true": "text.module.furnace.variant_b",
        "text.matter.fe.true": "text.matter.fe.variant_b",
        "text.poi.wreck.true": "text.poi.wreck.variant_b",
        "text.source.hand.true": "text.source.hand.variant_b"
    ]

    private static let prefixes: [(String, String)] = [
        ("reason.manifest.", "reason.roster."),
        ("reason.imprint.", "reason.grant.")
    ]

    /// 古い名前が 1 つも無いデータは、そのまま返す(作り直さない。数の書き方も変えない)。
    public static func translate(json data: Data) -> Data {
        guard mayContainLegacy(data) else { return data }
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return data }
        // 逃がしがあるだけで前の振り分けを通ったデータは、読んだ後に本当に古い名前があるかを見る(無ければ作り直さない)
        guard containsLegacy(object) else { return data }
        guard let translated = translate(object), JSONSerialization.isValidJSONObject(translated) else { return data }
        return (try? JSONSerialization.data(withJSONObject: translated)) ?? data
    }

    /// Test support for producing a pre-migration payload without duplicating names elsewhere.
    public static func legacy(json data: Data) -> Data {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return data }
        guard let translated = legacy(object), JSONSerialization.isValidJSONObject(translated) else { return data }
        return (try? JSONSerialization.data(withJSONObject: translated)) ?? data
    }

    public static func translate(_ value: Value) -> Value {
        switch value {
        case .object(let object):
            return .object(merged(object.map { ($0.key, replacement(for: $0.key), translate($0.value)) }))
        case .array(let values): return .array(values.map(translate))
        case .string(let string): return .string(replacement(for: string))
        default: return value
        }
    }

    /// Test support for pre-migration save payloads.
    public static func legacy(_ value: Value) -> Value {
        switch value {
        case .object(let object):
            return .object(merged(object.map { ($0.key, legacyName(for: $0.key), legacy($0.value)) }))
        case .array(let values): return .array(values.map(legacy))
        case .string(let string): return .string(legacyName(for: string))
        default: return value
        }
    }

    private static func translate(_ object: Any) -> Any? {
        if let dictionary = object as? [String: Any] {
            return merged(dictionary.compactMap { key, value in
                translate(value).map { (key, replacement(for: key), $0) }
            })
        }
        if let array = object as? [Any] { return array.compactMap(translate) }
        if let string = object as? String { return replacement(for: string) }
        return object
    }

    private static func legacy(_ object: Any) -> Any? {
        if let dictionary = object as? [String: Any] {
            return merged(dictionary.compactMap { key, value in
                legacy(value).map { (key, legacyName(for: key), $0) }
            })
        }
        if let array = object as? [Any] { return array.compactMap(legacy) }
        if let string = object as? String { return legacyName(for: string) }
        return object
    }

    /// 名前を替えた後に同じキーが 2 つになったら(古い名前と新しい名前が両方あるデータ)、落ちずに、
    /// もとから新しい名前で書かれていた方を残す。
    private static func merged<V>(_ entries: [(original: String, key: String, value: V)]) -> [String: V] {
        var out: [String: V] = [:]
        var fromOriginal: Set<String> = []
        for e in entries {
            let isOriginal = e.original == e.key
            if out[e.key] != nil, fromOriginal.contains(e.key), !isOriginal { continue }
            out[e.key] = e.value
            if isOriginal { fromOriginal.insert(e.key) }
        }
        return out
    }

    /// 読んだ JSON の中に、古い名前のキーか文字列があるか。
    private static func containsLegacy(_ object: Any) -> Bool {
        func isLegacy(_ string: String) -> Bool {
            exact[string] != nil || prefixes.contains { string.hasPrefix($0.0) }
        }
        if let dictionary = object as? [String: Any] {
            return dictionary.contains { isLegacy($0.key) || containsLegacy($0.value) }
        }
        if let array = object as? [Any] { return array.contains { containsLegacy($0) } }
        if let string = object as? String { return isLegacy(string) }
        return false
    }

    /// 古い名前の文字列(引用符つき、または接頭辞)がデータの中にあるか。
    /// JSON の文字列の中に逃がし(`\u0061` など)があると、古い名前がバイトの並びでは見つからないので、
    /// 逃がしが 1 つでもあれば「あるかもしれない」とする(読み替えを飛ばさない)。
    static func mayContainLegacy(_ data: Data) -> Bool {
        if data.range(of: Data("\\u".utf8)) != nil { return true }
        let needles = exact.keys.map { "\"\($0)\"" } + prefixes.map { "\"\($0.0)" }
        return needles.contains { data.range(of: Data($0.utf8)) != nil }
    }

    private static func replacement(for string: String) -> String {
        if let replacement = exact[string] { return replacement }
        for (old, new) in prefixes where string.hasPrefix(old) {
            return new + string.dropFirst(old.count)
        }
        return string
    }

    private static func legacyName(for string: String) -> String {
        if let replacement = exact.first(where: { $0.value == string })?.key { return replacement }
        for (old, new) in prefixes where string.hasPrefix(new) {
            return old + string.dropFirst(new.count)
        }
        return string
    }
}
