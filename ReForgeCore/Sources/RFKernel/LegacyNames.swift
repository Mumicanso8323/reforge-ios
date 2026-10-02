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
        "imprint.refuse": "grant.refuse"
    ]

    private static let prefixes: [(String, String)] = [
        ("reason.manifest.", "reason.roster."),
        ("reason.imprint.", "reason.grant.")
    ]

    public static func translate(json data: Data) -> Data {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return data }
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
            return .object(Dictionary(uniqueKeysWithValues: object.map { (replacement(for: $0.key), translate($0.value)) }))
        case .array(let values): return .array(values.map(translate))
        case .string(let string): return .string(replacement(for: string))
        default: return value
        }
    }

    /// Test support for pre-migration save payloads.
    public static func legacy(_ value: Value) -> Value {
        switch value {
        case .object(let object):
            return .object(Dictionary(uniqueKeysWithValues: object.map { (legacyName(for: $0.key), legacy($0.value)) }))
        case .array(let values): return .array(values.map(legacy))
        case .string(let string): return .string(legacyName(for: string))
        default: return value
        }
    }

    private static func translate(_ object: Any) -> Any? {
        if let dictionary = object as? [String: Any] {
            return Dictionary(uniqueKeysWithValues: dictionary.compactMap { key, value in
                translate(value).map { (replacement(for: key), $0) }
            })
        }
        if let array = object as? [Any] { return array.compactMap(translate) }
        if let string = object as? String { return replacement(for: string) }
        return object
    }

    private static func legacy(_ object: Any) -> Any? {
        if let dictionary = object as? [String: Any] {
            return Dictionary(uniqueKeysWithValues: dictionary.compactMap { key, value in
                legacy(value).map { (legacyName(for: key), $0) }
            })
        }
        if let array = object as? [Any] { return array.compactMap(legacy) }
        if let string = object as? String { return legacyName(for: string) }
        return object
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
