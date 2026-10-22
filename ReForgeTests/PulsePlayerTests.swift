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

    func testHapticsAreNotTighterThanGap() throws {
        let s = try settings()
        let haptics = RecordingHaptics()
        let player = PulsePlayer(sounds: RecordingSounds(), haptics: haptics, settings: s, reduceMotion: { false },
                                 clock: { 10 }, bannerStub: { $0 })
        player.press()
        player.press()
        XCTAssertEqual(haptics.feels.count, 1, "0.3 秒より詰めて打たない")
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
