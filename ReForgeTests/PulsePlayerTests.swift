import XCTest
import ReForgeEngine
@testable import ReForge

/// PT-B3 手応え。音の名前が束にある・触覚の切で触覚の呼び出しが 0 回・「動きを減らす」で浮かぶ文字を作らない。
@MainActor
final class PulsePlayerTests: XCTestCase {
    final class RecordingSounds: SoundPlaying {
        var played: [(UISound, Double)] = []
        func play(_ sound: UISound, volume: Double) { played.append((sound, volume)) }
    }

    final class RecordingHaptics: HapticFiring {
        var feels: [HapticFeel] = []
        func fire(_ cue: HapticCue) {}
        func ramp(intensity: Double) {}
        func play(_ feel: HapticFeel) { feels.append(feel) }
    }

    private func settings() throws -> PulseSettings {
        let name = "reforge.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return PulseSettings(defaults: defaults)
    }

    private func make(reduceMotion: Bool = false, haptics on: Bool = true)
        throws -> (PulsePlayer, RecordingSounds, RecordingHaptics) {
        let s = try settings()
        s.hapticsOn = on
        let sounds = RecordingSounds()
        let haptics = RecordingHaptics()
        var t = 0.0
        let player = PulsePlayer(sounds: sounds, haptics: haptics, settings: s, reduceMotion: { reduceMotion },
                                 clock: { t += 1; return t }, bannerStub: { $0 })
        return (player, sounds, haptics)
    }

    /// TEST-B3-4 「動きを減らす」の入で、浮かぶ文字を作らない。
    func testReduceMotionMakesNoFloaters() throws {
        let (calm, _, _) = try make(reduceMotion: true)
        calm.play([.unitDone(name: "x", count: 1)])
        XCTAssertTrue(calm.floaters.isEmpty)
        let (normal, _, _) = try make()
        normal.play([.unitDone(name: "x", count: 1)])
        XCTAssertEqual(normal.floaters.map(\.text), ["+1 x"])
        for _ in 0..<8 { normal.play([.unitDone(name: "x", count: 1)]) }
        XCTAssertEqual(normal.floaters.count, PulsePlayer.maxFloaters)
    }

    /// TEST-B3-5 触覚の切で、触覚の呼び出しが 0 回(音は鳴る)。
    func testHapticsOffMakesNoHapticCalls() throws {
        let (player, sounds, haptics) = try make(haptics: false)
        player.press()
        player.play([.placed, .firstTime(name: "x"), .fire(.out), .decisionShown])
        XCTAssertEqual(haptics.feels.count, 0)
        XCTAssertFalse(sounds.played.isEmpty)
        let (on, _, onHaptics) = try make(haptics: true)
        on.press()
        XCTAssertEqual(onHaptics.feels, [.select])
    }

    /// 触覚は 0.3 秒より詰めて打たない(合図・断り・手応えが通る 1 つの門)。
    func testHapticGateAllowsOnlyAfterGap() {
        var gate = HapticGate()
        XCTAssertTrue(gate.allow(at: 10))
        XCTAssertFalse(gate.allow(at: 10.2))
        XCTAssertTrue(gate.allow(at: 10.3))
    }

    /// こする音は 0.35 秒おき。
    func testRubSoundGap() throws {
        let s = try settings()
        let sounds = RecordingSounds()
        var t = 100.0
        let player = PulsePlayer(sounds: sounds, haptics: RecordingHaptics(), settings: s, reduceMotion: { false }, clock: { t })
        player.rub()
        t += 0.2
        player.rub()
        XCTAssertEqual(sounds.played.count, 1)
        t += 0.2
        player.rub()
        XCTAssertEqual(sounds.played.map(\.0), [.rub, .rub])
    }

    /// 帯の文は本物の表の道(物の名前の引数つき)で引く。
    func testBannerUsesRealTextTable() throws {
        let content = try AppModel.loadBundledContent(bundle: .main)
        UIText.shared.configure(tables: content.textTables, language: .ja, markFallback: false)
        addTeardownBlock { UIText.shared.configure(tables: content.textTables, language: .ja, markFallback: false) }
        let real = PulsePlayer(sounds: RecordingSounds(), haptics: RecordingHaptics(), settings: try settings())
        real.play([.finished(name: "XYZ")])
        XCTAssertEqual(real.banner, UIText.shared.string("ui.band.pulse_done", ["name": .string("XYZ")]))
        XCTAssertTrue(real.banner?.contains("XYZ") == true)
    }

    /// INV-B3-2 音・触覚を切っても入れても、同じ命令の列で世界は同じ。
    /// 断られる命令(手作業・置く)を混ぜるので、どちらの store でも脈(断られた)が必ず出る。出たことも確かめる。
    func testWorldIsSameWithAndWithoutSoundAndHaptics() async throws {
        let c = try AppModel.loadBundledContent(bundle: .main)
        func run(volume: Int, haptics: Bool) async throws -> (WorldState, Int) {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
            let s = try settings()
            s.volume = volume
            s.hapticsOn = haptics
            let sounds = RecordingSounds()
            let player = PulsePlayer(sounds: sounds, haptics: RecordingHaptics(), settings: s)
            let store = GameStore(content: c, world: GameBootstrap.newWorld(content: c, seed: 3),
                                  saves: FileSaveStorage(directory: dir), defaults: try XCTUnwrap(UserDefaults(suiteName: "reforge.tests.\(UUID().uuidString)")),
                                  pulsePlayer: player)
            await store.load()
            let origin = WorldPoint(.surface, GridPoint(0, 0))
            let commands: [Command] = [
                .production(.handwork(id: "handwork.test.none", input: nil, holding: true)),
                .production(.place(module: "test.none", at: origin, facing: .east)),
                .production(.handwork(id: "handwork.test.none", input: nil, holding: false)),
            ]
            for command in commands {
                _ = await store.perform(command)
                await store.clockStep(realSeconds: 0.5)
            }
            return (await store.host.world, sounds.played.count)
        }
        let quiet = try await run(volume: 0, haptics: false)
        let loud = try await run(volume: 100, haptics: true)
        XCTAssertGreaterThanOrEqual(quiet.1, 1, "脈が出た(音の口は音量 0 でも呼ばれる)")
        XCTAssertGreaterThanOrEqual(loud.1, 1, "脈が出た")
        XCTAssertEqual(quiet.1, loud.1)
        XCTAssertEqual(quiet.0, loud.0)
    }

    func testFeedSoundsCycleAndVolumeDefault() throws {
        let (player, sounds, _) = try make()
        player.play([.fed, .fed, .fed, .fed])
        XCTAssertEqual(sounds.played.map(\.0), [.feed1, .feed2, .feed3, .feed1])
        XCTAssertEqual(sounds.played[0].1, Double(PulseSettings.defaultVolume) / 100, accuracy: 0.0001)
    }

    /// TEST-B3-6 12 個の音の名前が全部、束の中にある。
    func testAllTwelveSoundsAreInBundle() {
        XCTAssertEqual(UISound.allCases.count, 12)
        let bundle = Bundle(for: GameStore.self)
        for sound in UISound.allCases {
            XCTAssertNotNil(bundle.url(forResource: sound.rawValue, withExtension: "wav"), sound.rawValue)
        }
    }

    /// 帯の文は表の ID を引く(物の名前を差し込む)。2.5 秒で消える仕組みの前に、出る文を確かめる。
    func testBannerAndTicks() throws {
        let (player, _, _) = try make()
        player.play([.finished(name: "x")])
        XCTAssertEqual(player.banner, "ui.band.pulse_done")
        XCTAssertEqual(player.doneTick, 1)
        player.play([.fire(.weakened)])
        XCTAssertEqual(player.banner, "ui.band.pulse_fire_down")
    }
}
