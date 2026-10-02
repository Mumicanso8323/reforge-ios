import CoreGraphics
import ReForgeEngine

/// 操作棒の画面上の計算。状態を持たないので、端末なしで表を確かめられる。
enum StickMath {
    static func direction(offset: CGSize, previous: StickDirection?, directions: Int, neutralRadius: CGFloat) -> StickDirection? {
        let distance = hypot(offset.width, offset.height)
        guard distance > neutralRadius else { return nil }
        let count = directions == 4 ? 4 : 8
        let angle = atan2(offset.height, offset.width)
        let raw = nearest(angle: angle, count: count)
        guard count == 8 else { return raw }
        guard let previous else { return raw }
        let boundary = angularDistance(angle, directionAngle(previous))
        // 8 度の余白の内側では、前の向きを保つ。
        return boundary <= (.pi / 8 + 8 * .pi / 180) ? previous : raw
    }

    static func knobOffset(_ offset: CGSize, limit: CGFloat = 48) -> CGSize {
        let d = hypot(offset.width, offset.height)
        guard d > limit, d > 0 else { return offset }
        return CGSize(width: offset.width * limit / d, height: offset.height * limit / d)
    }

    private static func nearest(angle: CGFloat, count: Int) -> StickDirection {
        let step = 2 * CGFloat.pi / CGFloat(count)
        let index = Int((angle / step).rounded()).modulo(count)
        if count == 4 {
            return [.east, .south, .west, .north][index]
        }
        return [.east, .southEast, .south, .southWest, .west, .northWest, .north, .northEast][index]
    }

    private static func directionAngle(_ direction: StickDirection) -> CGFloat {
        switch direction {
        case .east: 0
        case .southEast: .pi / 4
        case .south: .pi / 2
        case .southWest: 3 * .pi / 4
        case .west: .pi
        case .northWest: -3 * .pi / 4
        case .north: -.pi / 2
        case .northEast: -.pi / 4
        }
    }

    private static func angularDistance(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        abs(atan2(sin(a - b), cos(a - b)))
    }
}

private extension Int {
    func modulo(_ n: Int) -> Int { ((self % n) + n) % n }
}
