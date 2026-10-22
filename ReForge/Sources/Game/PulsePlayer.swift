import AVFoundation
import Foundation
import Observation
import UIKit
import ReForgeEngine

/// 効果音の名前(PT-B3)。束の中の Sounds/<名前>.wav。本物の音は同じ名前で差し替える。曲は入れない。
enum UISound: String, CaseIterable {
    case press = "ui_press", rub = "ui_rub", unit = "ui_unit", place = "ui_place", done = "ui_done"
    case reject = "ui_reject", feed1 = "ui_feed_1", feed2 = "ui_feed_2", feed3 = "ui_feed_3"
    case ignite = "ui_ignite", fireDown = "ui_fire_down", night = "ui_night"
}

/// 効果音の音量(0〜100)と触覚の入切。UserDefaults に置く(保存には入れない)。
struct PulseSettings {
    /// 効果音の音量の既定。ゲームに音を付けるかはオーナーの決め待ち。変えるのはここ 1 か所。
    static let defaultVolume = 70
    static let volumeKey = "reforge.effectVolume"
    static let hapticsKey = "reforge.hapticsOn"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var volume: Int {
        get { defaults.object(forKey: Self.volumeKey) == nil ? Self.defaultVolume : min(max(defaults.integer(forKey: Self.volumeKey), 0), 100) }
        nonmutating set { defaults.set(min(max(newValue, 0), 100), forKey: Self.volumeKey) }
    }

    var hapticsOn: Bool {
        get { defaults.object(forKey: Self.hapticsKey) == nil ? true : defaults.bool(forKey: Self.hapticsKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.hapticsKey) }
    }
}

/// 音の口。実機は AVAudioPlayer を前もって読み込んで鳴らし、試験は記録するだけの物に差し替える。
@MainActor
protocol SoundPlaying: AnyObject {
    func play(_ sound: UISound, volume: Double)
}

/// `.ambient`(ほかのアプリの音楽を止めない・消音スイッチで消える)。短い音は最初に読み込む(初回の遅れを避ける)。
@MainActor
final class SystemSounds: SoundPlaying {
    /// アプリ全体で 1 つ(12 個の wav を読むのは最初の 1 回だけ)。
    static let shared = SystemSounds()

    private var players: [UISound: AVAudioPlayer] = [:]

    init(bundle: Bundle = .main) {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        for sound in UISound.allCases {
            guard let url = bundle.url(forResource: sound.rawValue, withExtension: "wav"),
                  let player = try? AVAudioPlayer(contentsOf: url) else { continue }
            player.prepareToPlay()
            players[sound] = player
        }
    }

    func play(_ sound: UISound, volume: Double) {
        guard volume > 0, let player = players[sound] else { return }
        player.volume = Float(volume)
        player.currentTime = 0
        player.play()
    }
}

/// 音を鳴らさない口(試験の store が wav を読まないための物)。
@MainActor
final class SilentSounds: SoundPlaying {
    func play(_ sound: UISound, volume: Double) {}
}

/// 浮かぶ文字(「+1 〈物〉」)。固定の形 + 物の名前だけ。
struct Floater: Identifiable, Equatable {
    let id: Int
    let text: String
}

/// 手応え(Frame.pulses)を音・触覚・浮かぶ文字にする。世界は見ない・変えない(INV-B3-2)。
/// 押した瞬間の反応(press)は本体の応答を待たず、ボタンの押下から直接呼ぶ(INV-B3-1)。
/// 音と触覚のどちらも、見た目か文字と組になる(INV-B3-3)。
@MainActor
@Observable
final class PulsePlayer {
    static let maxFloaters = 5
    static let floaterLifetime: TimeInterval = 0.5

    private(set) var floaters: [Floater] = []
    /// 帯の短い文(「〈物〉ができた」「初めての〈物〉」「火が弱まった」)。2.5 秒。説明や理由は入れない。
    private(set) var banner: String?
    /// 見た目の合図(増えるたびに、画面が 1 度光る・ふくらむ)。「動きを減らす」でも色の変化は出す。
    private(set) var unitTick = 0
    private(set) var placedTick = 0
    private(set) var doneTick = 0
    private(set) var feedTick = 0
    private(set) var fireDownTick = 0

    @ObservationIgnored private let sounds: any SoundPlaying
    @ObservationIgnored private let haptics: any HapticFiring
    @ObservationIgnored private let settings: PulseSettings
    @ObservationIgnored private let reduceMotion: () -> Bool
    @ObservationIgnored private let clock: () -> TimeInterval
    /// 試験だけが渡す、帯の文の代わり(ID をそのまま返すなど)。実機は nil で、固定文言の表から引く。
    @ObservationIgnored private let bannerStub: ((String) -> String)?
    @ObservationIgnored private var fedCount = 0
    @ObservationIgnored private var nextID = 0
    @ObservationIgnored private var bannerTask: Task<Void, Never>?
    @ObservationIgnored private var lastRub: TimeInterval = -.infinity
    static let bannerLifetime: TimeInterval = 2.5
    static let rubGap: TimeInterval = 0.35

    init(sounds: (any SoundPlaying)? = nil, haptics: any HapticFiring, settings: PulseSettings = PulseSettings(),
         reduceMotion: @escaping () -> Bool = { UIAccessibility.isReduceMotionEnabled },
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         bannerStub: ((String) -> String)? = nil) {
        self.bannerStub = bannerStub
        self.sounds = sounds ?? SystemSounds.shared
        self.haptics = haptics
        self.settings = settings
        self.reduceMotion = reduceMotion
        self.clock = clock
    }

    /// ボタンを押した瞬間(音 ui_press と軽い選択の触覚)。
    func press() {
        play(.press)
        feel(.select)
    }

    /// 火起こしの長押しの間(進みが動くたび)。ui_rub は 0.35 秒おき。触覚は暗い場面の長押しの ramp(HapticRamp)が鳴らす。
    func rub() {
        let t = clock()
        guard t - lastRub >= Self.rubGap else { return }
        lastRub = t
        play(.rub)
    }

    func play(_ pulses: [Pulse]) {
        for pulse in pulses { play(pulse) }
    }

    private func play(_ pulse: Pulse) {
        switch pulse {
        case .unitDone(let name, let count):
            play(.unit)
            unitTick += 1
            float("+\(count) \(name)")
        case .placed:
            play(.place)
            feel(.select)
            placedTick += 1
        case .finished(let name):
            play(.done, scale: 0.8)  // 成功の触覚は既存の経路(HapticCue.built)が鳴らす
            doneTick += 1
            show(banner: bannerStub?("ui.band.pulse_done") ?? UIText.shared.string("ui.band.pulse_done", ["name": .string(name)]))
        case .firstTime(let name):
            play(.done)
            feel(.success)
            doneTick += 2
            show(banner: bannerStub?("ui.band.pulse_first") ?? UIText.shared.string("ui.band.pulse_first", ["name": .string(name)]))
        case .rejected:
            play(.reject)  // 弱い触覚(nudge)と揺れは store.show(notice:) が鳴らす
        case .fed:
            fedCount = fedCount % 3 + 1
            play([.feed1, .feed2, .feed3][fedCount - 1])
            feedTick += 1
        case .fire(.lit):
            play(.ignite)
        case .fire(.weakened), .fire(.out):
            play(.fireDown)
            feel(.fireDown)
            fireDownTick += 1
            show(banner: bannerStub?("ui.band.pulse_fire_down") ?? UIText.shared.string("ui.band.pulse_fire_down"))
        case .nightBegan:
            play(.night)
        case .decisionShown:
            feel(.decision)
        }
    }

    private func show(banner text: String) {
        banner = text
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.bannerLifetime))
            guard !Task.isCancelled else { return }
            self?.banner = nil
        }
    }

    private func play(_ sound: UISound, scale: Double = 1) {
        sounds.play(sound, volume: Double(settings.volume) / 100 * scale)
    }

    private func feel(_ feel: HapticFeel) {
        guard settings.hapticsOn else { return }
        haptics.play(feel)  // 0.3 秒の間隔は触覚の口(SystemHaptics の HapticGate)が 1 か所で見る
    }

    /// 「動きを減らす」が入っているときは浮かぶ文字を作らない(色の変化だけ)。
    private func float(_ text: String) {
        guard !reduceMotion() else { return }
        nextID += 1
        let id = nextID
        floaters.append(Floater(id: id, text: text))
        if floaters.count > Self.maxFloaters { floaters.removeFirst(floaters.count - Self.maxFloaters) }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.floaterLifetime))
            self?.floaters.removeAll { $0.id == id }
        }
    }
}
