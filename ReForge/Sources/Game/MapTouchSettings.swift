import Foundation
import CoreGraphics
import ReForgeEngine

enum MapZoomPlan: String, CaseIterable {
    case a, b, c

    var levels: [Double] {
        switch self {
        case .a: [18, 24, 44]
        case .b: [24, 32, 44]
        case .c: [28, 36, 44]
        }
    }

    var defaultZoom: Int {
        switch self {
        case .a, .b, .c: 2
        }
    }
}

enum MapTouchSettings {
    static let defaults = UserDefaults.standard
    static let handKey = "mapTouchHand"
    static let directionsKey = "mapTouchDirections"
    static let neutralKey = "mapTouchNeutral"
    static let tapWalkKey = "mapTouchTapWalk"
    static let stickPlacementKey = "mapTouchStickPlacement"
    static let zoomPlanKey = "mapTouchZoomPlan"
    static let autoReturnKey = "mapTouchAutoReturn"

    static func hand(_ defaults: UserDefaults = .standard) -> HUDLayout.Hand {
        defaults.string(forKey: handKey) == HUDLayout.Hand.left.rawValue ? .left : .right
    }

    static func directions(_ defaults: UserDefaults = .standard) -> Int {
        defaults.integer(forKey: directionsKey) == 4 ? 4 : 8
    }

    static func neutralRadius(_ defaults: UserDefaults = .standard) -> CGFloat {
        switch defaults.integer(forKey: neutralKey) {
        case 10, 20: CGFloat(defaults.integer(forKey: neutralKey))
        default: 14
        }
    }

    static func zoomPlan(_ defaults: UserDefaults = .standard) -> MapZoomPlan {
        MapZoomPlan(rawValue: defaults.string(forKey: zoomPlanKey) ?? "b") ?? .b
    }
}
