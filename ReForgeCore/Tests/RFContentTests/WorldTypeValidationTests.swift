import Foundation
import RFContent
import RFKernel
import RFTestSupport
import XCTest

/// U16 の型の参照の検査と、JSON の形(U14 が生成器から書く形)が読めること。
final class WorldTypeValidationTests: XCTestCase {
    func load(_ json: String) throws -> ContentDB {
        var db = try TestContent.publicOnly()
        try ContentLoader.apply(json: Data(json.utf8), to: &db, name: "u16")
        return db
    }

    func testShapesLoadAndValidReferencesPass() throws {
        let db = try load("""
        {
          "mapGen": { "size": { "width": 96, "height": 96 }, "parameters": null,
                      "sites": [ { "id": "site.test.fort", "poi": "site.test.fort", "minDistance": 30, "maxDistance": 40 } ] },
          "groups": [ { "id": "group.test.fort", "relation": -10 } ],
          "people": [ { "id": "person.test_k", "name": "person:person.test_a", "specialties": [], "ideology": {},
                        "group": "group.test.fort", "home": "site.test.fort",
                        "tether": { "person": "person.noah", "radius": 5 } } ],
          "auras": [ { "id": "aura.test.quiet", "modifiers": [ { "repelEnemies": {} } ], "radius": 3,
                       "requiresNear": { "person": "person.noah", "radius": 6 } } ],
          "stats": [ { "id": "stat.test.air", "initial": 0, "perDay": 5, "mined": { "ores": ["rare"], "per": 10, "amount": 1 } } ],
          "events": [ { "id": "event.test.u16", "trigger": { "on": [], "when": { "always": {} } }, "effects": [
            { "destroyPlacements": { "near": { "trigger": {} }, "radius": 3, "max": 2 } },
            { "groupBattle": { "group": "group.test.fort", "at": { "base": {} }, "lethal": true } } ] } ]
        }
        """)
        XCTAssertEqual(db.people["person.test_k"]?.home, "site.test.fort")
        XCTAssertEqual(db.mapGen.sites?.first?.maxDistance, 40)
        let prefixes = ["site.", "person.", "aura.", "module.", "stat.", "effect."]
        let issues = ContentValidator.validate(db).filter { i in
            i.level == .error && prefixes.contains(where: { i.rule.hasPrefix($0) })
        }
        XCTAssertEqual(issues, [])
    }

    func testBrokenReferencesAreErrors() throws {
        let db = try load("""
        {
          "people": [ { "id": "person.test_k", "name": "person:person.test_a", "specialties": [], "ideology": {},
                        "tether": { "person": "person.nobody", "radius": 5 } } ],
          "events": [ { "id": "event.test.u16", "trigger": { "on": [], "when": { "always": {} } }, "effects": [
            { "destroyPlacements": { "near": { "base": {} }, "radius": 3, "module": "module.nothing" } },
            { "groupBattle": { "group": "group.nothing", "at": { "base": {} } } } ] } ]
        }
        """)
        let rules = Set(ContentValidator.validate(db).filter { $0.level == .error }.map(\.rule))
        XCTAssertTrue(rules.isSuperset(of: ["person.tether", "effect.destroy", "effect.groupBattle"]), "\(rules)")
    }
}
