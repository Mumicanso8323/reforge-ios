import RFKernel
import RFMap

/// U16(R3・R4 の世界の型)の参照の検査。型そのものは各定義に省略できる項目として足してある:
/// MapGenConfig.sites・PersonDef.home/tether・AuraDef.requiresNear・ModuleDef.power・StatDef.mined、
/// 効果 destroyPlacements・groupBattle。
extension ContentValidator {
    static func worldTypeRules(_ db: ContentDB, _ out: inout [Issue]) {
        func err(_ rule: String, _ msg: String) { out.append(Issue(level: .error, rule: rule, message: msg)) }
        func warn(_ rule: String, _ msg: String) { out.append(Issue(level: .warning, rule: rule, message: msg)) }
        let sites = db.mapGen.sites ?? []
        let sitePOIs = Set(sites.map(\.poi))
        var seen = Set<String>()
        for s in sites {
            if !seen.insert(s.id).inserted { err("site.id", "場所 \(s.id) が重なっている") }
            if s.minDistance < 0 || s.minDistance > s.maxDistance { err("site.distance", "場所 \(s.id) の距離の範囲が逆") }
        }
        for (id, p) in db.people.sorted(by: { $0.key < $1.key }) {
            if let t = p.tether, db.people[t.person] == nil { err("person.tether", "\(id) の縛りの人 \(t.person) が無い") }
            if let h = p.home, !sitePOIs.contains(h), db.pois[h] == nil {
                warn("person.home", "\(id) の居場所 \(h) が場所(mapGen.sites)にも POI の定義にも無い")
            }
            if let g = p.group, db.groups[g] == nil { err("person.group", "\(id) の集団 \(g) が無い") }
        }
        for (id, a) in db.auras.sorted(by: { $0.key < $1.key }) {
            if let t = a.requiresNear, db.people[t.person] == nil { err("aura.requiresNear", "\(id) の縛りの人 \(t.person) が無い") }
        }
        for (id, m) in db.modules.sorted(by: { $0.key < $1.key }) {
            guard let p = m.power else { continue }
            if (p.output ?? 0) < 0 || (p.draw ?? 0) < 0 { err("module.power", "\(id) の電力が負") }
            if (p.fuelPerDay ?? 0) > 0, p.fuel == nil { err("module.power", "\(id) は燃料の数があるのに燃料が無い") }
        }
        for (id, s) in db.stats.sorted(by: { $0.key < $1.key }) {
            if let m = s.mined, m.ores.isEmpty || (m.per ?? 1) < 1 { err("stat.mined", "\(id) の掘った量の項が不正") }
        }
        func checkEffects(_ es: [Effect]?, _ origin: String) {
            for e in es ?? [] {
                switch e {
                case .destroyPlacements(_, let r, let m, let s, let mx):
                    if r < 0 || (mx ?? 0) < 0 { err("effect.destroy", "\(origin) の壊す範囲が負") }
                    if let m, db.modules[m] == nil { err("effect.destroy", "\(origin) のモジュール \(m) が無い") }
                    if let s, db.structures[s] == nil { err("effect.destroy", "\(origin) の建造物 \(s) が無い") }
                case .groupBattle(let g, _, let members, _):
                    if db.groups[g] == nil { err("effect.groupBattle", "\(origin) の集団 \(g) が無い") }
                    for p in members ?? [] where db.people[p] == nil { err("effect.groupBattle", "\(origin) の人 \(p) が無い") }
                default: break
                }
            }
        }
        for (id, e) in db.events.sorted(by: { $0.key < $1.key }) {
            checkEffects(e.effects, "event \(id)")
            for ch in e.choices ?? [] { checkEffects(ch.effects, "event \(id) / \(ch.id)") }
        }
        for (id, o) in db.objectives.sorted(by: { $0.key < $1.key }) { checkEffects(o.effects, "objective \(id)") }
        for (id, en) in db.endings.sorted(by: { $0.key < $1.key }) { checkEffects(en.effects, "ending \(id)") }
        for (id, scene) in db.scenes.sorted(by: { $0.key < $1.key }) { checkEffects(scene.onEnd, "scene \(id)") }
    }
}
