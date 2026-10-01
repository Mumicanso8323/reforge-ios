import Foundation
import ReForgeEngine
import RFTestSupport
import XCTest

/// アプリの「つづきから」と同じ道筋(新しい世界 → SaveCodec で書く → 読む)が、本物のコンテンツと
/// 大きな種(アプリは UInt64 の全域から引く)でも元に戻ることを確かめる。
final class ResumeRoundTripTests: XCTestCase {
    private func roundTrip(_ content: ContentDB, seed: UInt64, file: StaticString = #filePath, line: UInt = #line) throws {
        let world = GameBootstrap.newWorld(content: content, seed: seed)
        let env = SaveEnvelope(slot: .resume, world: world,
                               content: content.layers.map { ContentStamp(layer: $0.id, version: $0.version) })
        let data = try SaveCodec.encode(env)
        let back: SaveEnvelope
        do { back = try SaveCodec.decode(data) } catch {
            return XCTFail("読み戻せない(seed \(seed)): \(error)", file: file, line: line)
        }
        XCTAssertEqual(back.world, world, "seed \(seed)", file: file, line: line)
    }

    func testResumeRoundTripPublicLargeSeeds() throws {
        let c = try TestContent.publicOnly()
        for seed: UInt64 in [3, UInt64(Int64.max) + 1, UInt64.max, 0x9E37_79B9_7F4A_7C15] {
            try roundTrip(c, seed: seed)
        }
    }

    func testResumeRoundTripFullContent() throws {
        try XCTSkipUnless(TestContent.hasPrivateLayer, "非公開の層が無い")
        let c = try TestContent.full()
        for seed: UInt64 in [3, UInt64.max, 0x9E37_79B9_7F4A_7C15] {
            try roundTrip(c, seed: seed)
        }
    }
}
