import RFContent
import RFKernel
import RFWorld

/// 1 次元の帯の上の自動戦闘(原作 BattleField の移植。combat-and-mechanics.md §8・§9)。
///
/// 1 手番: 動ける者が速さの順(同じなら味方が先、次に並びの順)に、届けば打ち、届かなければ動く(速さ / 2 マス)。
/// - 敵はいつも前に出る(最も近い相手へ)。
/// - 味方は方針に従う。前に出る = 最も近い敵へ詰める(与える傷 ×1.25・受ける傷 ×1.1)。
///   距離を取る = 届く一番遠い間合いを保つ。届かない武器なら動かずに待ち、来た相手を先に打つ。
///   近すぎれば(槍の内側)下がる。帯の端で下がれなければ、そのまま打つ。
/// - 撤退: 味方は手番の最初に 1 人ずつ抜けようとする(速さ・間合いで成否)。しくじると最寄りの敵に打たれる。
/// - 命中 = 70 + (速さの差) × 5 − 距離 × 10(10〜95%)。傷 = max(1, 攻撃 − 守り) × 80〜130% 、5% で 2 倍。
/// - 人は体力が downBelow を下回ると倒れて帯から外れる(lethal の戦いでは 0 で死ぬ)。
/// 乱数は渡された流れ(RFCombat の .combat)だけを使う。
public enum Lane {
    /// 手番を 1 つ進める。終わったら結果を返す(続くなら nil)。
    @discardableResult
    public static func resolveTurn(_ b: inout BattleState, def: CombatDef, rng: inout SeededRandom) -> BattleState.Outcome? {
        b.turn += 1
        b.beats = []
        if b.retreating { attemptEscape(&b, def: def, rng: &rng) }
        let order = b.units.indices.filter { b.units[$0].isActive }.sorted { x, y in
            let a = b.units[x], c = b.units[y]
            if a.speed != c.speed { return a.speed > c.speed }
            if a.side != c.side { return a.side == .allies }
            return x < y
        }
        for i in order {
            guard b.units[i].isActive else { continue }
            if b.units[i].side == .allies && b.retreating { continue }
            guard let t = nearestOpponent(of: i, in: b) else { break }
            let d = abs(b.units[t].position - b.units[i].position)
            if d >= b.units[i].reachMin && d <= b.units[i].reachMax {
                attack(i, t, &b, def: def, rng: &rng)
            } else {
                let before = b.units[i].position
                move(i, toward: t, &b)
                // 槍の内側に入られ、帯の端で下がれない: そのまま打つ
                if d < b.units[i].reachMin && b.units[i].position == before { attack(i, t, &b, def: def, rng: &rng) }
            }
        }
        return outcome(of: b)
    }

    /// いまの勝ち負け(続くなら nil)。
    public static func outcome(of b: BattleState) -> BattleState.Outcome? {
        let enemies = b.units.contains { $0.side == .enemies && $0.isActive }
        let allies = b.units.contains { $0.side == .allies && $0.isActive }
        if !enemies { return .won }
        if !allies {
            return b.units.contains { $0.side == .allies && $0.state == .escaped } ? .fled : .lost
        }
        return nil
    }

    static func nearestOpponent(of i: Int, in b: BattleState) -> Int? {
        let me = b.units[i]
        return b.units.indices
            .filter { b.units[$0].side != me.side && b.units[$0].isActive }
            .min { x, y in
                let dx = abs(b.units[x].position - me.position), dy = abs(b.units[y].position - me.position)
                return dx != dy ? dx < dy : x < y
            }
    }

    static func attack(_ a: Int, _ t: Int, _ b: inout BattleState, def: CombatDef, rng: inout SeededRandom) {
        let attacker = b.units[a], target = b.units[t]
        let d = abs(attacker.position - target.position)
        let hit = min(95, max(10, 70 + (attacker.speed - target.speed) * 5 - d * 10))
        guard rng.int(below: 100) < hit else {
            b.beats.append(BattleBeat(actor: a, target: t, act: .miss))
            return
        }
        var dmg = max(1, attacker.attack - target.defense) * rng.int(in: 80...130) / 100
        if b.stance == .advance {
            if attacker.side == .allies { dmg = dmg * def.advanceDealt / 1000 }
            if target.side == .allies { dmg = dmg * def.advanceTaken / 1000 }
        }
        dmg = max(1, dmg)
        let crit = rng.int(below: 100) < 5
        if crit { dmg *= 2 }
        b.units[t].hp -= dmg
        b.units[t].damageTaken += dmg
        if target.side == .allies {
            if b.lethal && b.units[t].hp <= 0 {
                b.units[t].state = .dead
            } else if b.units[t].hp < def.down {
                b.units[t].state = .down
            }
        } else if b.units[t].hp <= 0 {
            b.units[t].state = .dead
            b.units[a].kills += 1
        }
        b.beats.append(BattleBeat(actor: a, target: t, act: .hit, damage: dmg, critical: crit))
    }

    static func move(_ i: Int, toward t: Int, _ b: inout BattleState) {
        let u = b.units[i]
        let other = b.units[t].position
        let d = abs(other - u.position)
        let dir = other > u.position ? 1 : (other < u.position ? -1 : (u.side == .allies ? 1 : -1))
        let step = max(1, u.speed / 2)
        var delta = 0
        if d > u.reachMax {
            // 届かない: 敵と「前に出る」味方は詰める。「距離を取る」味方は待つ(相手が来る)。
            if u.side == .enemies || b.stance == .advance { delta = dir * min(step, d - u.reachMax) }
        } else if d < u.reachMin {
            // 近すぎる(槍の内側): 下がる。
            delta = -dir * min(step, u.reachMin - d)
        }
        let to = min(b.laneSize - 1, max(0, u.position + delta))
        guard to != u.position else { return }
        b.units[i].position = to
        b.beats.append(BattleBeat(actor: i, target: nil, act: .move))
    }

    static func attemptEscape(_ b: inout BattleState, def: CombatDef, rng: inout SeededRandom) {
        let enemySpeed = b.units.filter { $0.side == .enemies && $0.isActive }.map(\.speed).max() ?? 0
        for i in b.units.indices where b.units[i].side == .allies && b.units[i].isActive {
            guard let e = nearestOpponent(of: i, in: b) else { return }
            let d = abs(b.units[e].position - b.units[i].position)
            let chance = min(95, max(5, def.retreat + (b.units[i].speed - enemySpeed) * 5 + d * 10))
            if rng.int(below: 100) < chance {
                b.units[i].state = .escaped
                b.beats.append(BattleBeat(actor: i, target: nil, act: .escape))
            } else {
                b.beats.append(BattleBeat(actor: i, target: e, act: .caught))
                attack(e, i, &b, def: def, rng: &rng)  // 背中を打たれる
            }
        }
    }
}
