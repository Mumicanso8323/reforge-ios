import UIKit

/// 背面へ移るときに保存の完了までアプリを保つ口。試験では差し替えられる。
@MainActor
protocol BackgroundTaskManaging {
    func begin(name: String, expirationHandler: @escaping () -> Void) -> UIBackgroundTaskIdentifier
    func end(_ identifier: UIBackgroundTaskIdentifier)
}

@MainActor
struct ApplicationBackgroundTasks: BackgroundTaskManaging {
    /// AppModel.init の既定の引数(主スレッドに縛られない文脈で評価される)から作れるように。
    nonisolated init() {}

    func begin(name: String, expirationHandler: @escaping () -> Void) -> UIBackgroundTaskIdentifier {
        UIApplication.shared.beginBackgroundTask(withName: name, expirationHandler: expirationHandler)
    }

    func end(_ identifier: UIBackgroundTaskIdentifier) {
        UIApplication.shared.endBackgroundTask(identifier)
    }
}
