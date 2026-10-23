import StoreKit

/// 入れ方の種別。StoreKit 2 の `AppTransaction.environment` を、試験で差し替えられる形にしたもの。
enum DistributionEnvironment: Equatable {
    case production
    case sandbox
    case xcode
}

/// 入れ方を読む口。取れない・検証に失敗したときは nil を返す(門は閉じる側に倒す)。
typealias DistributionEnvironmentReader = @Sendable () async -> DistributionEnvironment?

enum DistributionGate {
    /// TestFlight(sandbox)か Xcode から入れた版だけ true。App Store の版・取れない時は false。
    static func opensGate(_ environment: DistributionEnvironment?) -> Bool {
        switch environment {
        case .sandbox, .xcode: return true
        case .production, .none: return false
        }
    }

    static let storeKitReader: DistributionEnvironmentReader = {
        guard case .verified(let transaction) = try? await AppTransaction.shared else { return nil }
        switch transaction.environment {
        case .production: return .production
        case .sandbox: return .sandbox
        case .xcode: return .xcode
        default: return nil
        }
    }
}
