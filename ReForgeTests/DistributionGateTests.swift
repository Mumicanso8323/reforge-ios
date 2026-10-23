import XCTest
import ReForgeEngine
@testable import ReForge

@MainActor
final class DistributionGateTests: XCTestCase {
    private func tempSaves() -> FileSaveStorage {
        FileSaveStorage(directory: FileManager.default.temporaryDirectory.appendingPathComponent("gate-\(UUID().uuidString)"))
    }

    private func opened(_ env: DistributionEnvironment?) async -> Bool {
        let app = AppModel(saves: tempSaves(), distributionReader: { env })
        await app.loadDistributionGate()
        return app.distributionGateOpen
    }

    func testSandboxAndXcodeOpenGate() async {
        let sandbox = await opened(.sandbox)
        let xcode = await opened(.xcode)
        XCTAssertTrue(sandbox)
        XCTAssertTrue(xcode)
    }

    func testProductionKeepsGateClosed() async {
        let production = await opened(.production)
        XCTAssertFalse(production)
    }

    func testReadFailureKeepsGateClosed() async {
        let failed = await opened(nil)
        XCTAssertFalse(failed)
    }
}
