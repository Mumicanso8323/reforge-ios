import RFContent
import RFKernel
import RFMap
import RFPresent
import RFRules
import RFSim
import RFTestSupport
import RFWorld
import XCTest

final class TimeOfDayScreenTests: XCTestCase {
    private func chunks(_ builder: FrameBuilder, _ world: WorldState, _ frame: Frame) -> [MapChunk] {
        builder.chunks(world, Array(frame.map.chunkRevisions.indices), map: frame.map)
    }

    private func know(_ world: inout WorldState, _ points: [GridPoint]) {
        var bits = world.knowledge.mapKnown[.surface] ?? GridBitset(size: world.map[.surface]!.size)
        for point in points { bits[point] = true }
        world.knowledge.mapKnown[.surface] = bits
    }

    private func assertUnchangedChunksMatch(_ old: Frame, _ oldChunks: [MapChunk],
                                            _ new: Frame, _ newChunks: [MapChunk], file: StaticString = #filePath,
                                            line: UInt = #line) {
        let oldByIndex = Dictionary(uniqueKeysWithValues: oldChunks.map { ($0.index, $0) })
        let newByIndex = Dictionary(uniqueKeysWithValues: newChunks.map { ($0.index, $0) })
        for index in old.map.chunkRevisions.indices where old.map.chunkRevisions[index] == new.map.chunkRevisions[index] {
            XCTAssertEqual(newByIndex[index]?.tiles, oldByIndex[index]?.tiles, "chunk \(index) tiles", file: file, line: line)
            XCTAssertEqual(newByIndex[index]?.timeTint, oldByIndex[index]?.timeTint, "chunk \(index) tint", file: file, line: line)
        }
    }

    func testDayBarDotsFollowMarkChangesAndCompatibilityDefinition() throws {
        let content = try TestContent.publicOnly()
        let def = try XCTUnwrap(content.timeTint)
        let publicDots = TimeOfDay.dayBarDots(def, clock: content.clock)
        XCTAssertEqual(publicDots, [0, 187, 750, 1000])

        let fallbackDots = TimeOfDay.dayBarDots(TimeOfDay.defaultDef(content.clock), clock: content.clock)
        XCTAssertEqual(fallbackDots, [0, 1000])
        for dots in [publicDots, fallbackDots] {
            XCTAssertEqual(dots.first, 0)
            XCTAssertEqual(dots.last, 1000)
            XCTAssertEqual(dots, Array(Set(dots)).sorted())
        }
    }

    func testFrameTimeWordUsesTheTimeMarkTableOrNil() throws {
        let content = try TestContent.publicOnly()
        let def = try XCTUnwrap(content.timeTint)
        let builder = FrameBuilder(content: content)
        for key in def.keys {
            var world = TestRig(content: content).factory.newWorld(seed: 1)
            world.clock.now = GameTime(seconds: Int64(key.at * 60))
            world.clock.phase = key.at < content.clock.dayGameHours * 60 ? .day : .nightWork
            let frame = builder.build(world, revision: key.at + 1, previous: nil, report: nil)
            XCTAssertEqual(frame.timeWord, content.texts[TimeOfDay.wordID(frame.timeMark)])
        }

        var withoutWords = content
        for mark in TimeMark.allCases { withoutWords.texts.removeValue(forKey: TimeOfDay.wordID(mark)) }
        let world = TestRig(content: withoutWords).factory.newWorld(seed: 1)
        let frame = FrameBuilder(content: withoutWords).build(world, revision: 1, previous: nil, report: nil)
        XCTAssertNil(frame.timeWord)
    }

    func testEqualChunkRevisionKeepsTilesAndTintEqualAcrossVisionChanges() throws {
        let content = try TestContent.publicOnly()
        let builder = FrameBuilder(content: content)
        var world = TestRig(content: content).factory.newWorld(seed: 1)
        know(&world, [GridPoint(1, 1), GridPoint(17, 1), GridPoint(1, 17), GridPoint(17, 17)])

        let first = builder.build(world, revision: 1, previous: nil, report: nil)
        let firstChunks = chunks(builder, world, first)
        world.people[.noah]!.position = WorldPoint(.surface, GridPoint(4, 4))
        let second = builder.build(world, revision: 2, previous: first, report: StepReport())
        let secondChunks = chunks(builder, world, second)
        XCTAssertTrue(zip(first.map.chunkRevisions, second.map.chunkRevisions).contains { $0 == $1 })
        assertUnchangedChunksMatch(first, firstChunks, second, secondChunks)

        world.clock.now = GameTime(seconds: 8 * 60)
        let stepped = builder.build(world, revision: 3, previous: second, report: StepReport())
        XCTAssertTrue(zip(second.map.chunkRevisions, stepped.map.chunkRevisions).allSatisfy { $1 > $0 })
        XCTAssertTrue(chunks(builder, world, stepped).allSatisfy { $0.timeTint == stepped.timeTint })
    }

    func testTimeStepAndVisionOnlyAdvanceAffectedKnownChunks() throws {
        let content = try TestContent.publicOnly()
        let builder = FrameBuilder(content: content)
        var world = TestRig(content: content).factory.newWorld(seed: 1)
        know(&world, [GridPoint(1, 1)])
        let first = builder.build(world, revision: 1, previous: nil, report: nil)

        world.clock.now = GameTime(seconds: 8 * 60)
        let stepped = builder.build(world, revision: 2, previous: first, report: StepReport())
        XCTAssertEqual(stepped.map.chunkRevisions, [2, 1, 1, 1])

        world.people[.noah]!.position = WorldPoint(.surface, GridPoint(4, 4))
        let walked = builder.build(world, revision: 3, previous: stepped, report: StepReport())
        XCTAssertEqual(walked.map.chunkRevisions, [3, 1, 1, 1])
    }

    func testNightHearthClassOnlyInvalidatesAffectedKnownChunk() throws {
        let content = try TestContent.publicOnly()
        let builder = FrameBuilder(content: content)
        var world = TestRig(content: content).factory.newWorld(seed: 1)
        let center = world.map.spawn.point
        know(&world, [center + GridPoint(3, 0), GridPoint(1, 1)])
        world.clock.phase = .nightWork
        world.clock.now = GameTime(seconds: 480 * 60)
        let before = builder.build(world, revision: 1, previous: nil, report: nil)
        let beforeChunks = chunks(builder, world, before)

        let fire = world.newEntityID()
        var camp = Placement(id: fire, kind: .structure("structure.campfire"), at: WorldPoint(.surface, center), facing: .north,
                             origin: ProvenanceLedger.unknownOrigin, status: .running)
        var hearth = StructureRuntime()
        hearth.hearth = HearthState(fuel: 43_200_000, lit: true)
        camp.structure = hearth
        world.placements.items[fire] = camp

        let after = builder.build(world, revision: 2, previous: before, report: StepReport())
        let afterChunks = chunks(builder, world, after)
        XCTAssertNotEqual(after.map.chunkRevisions, before.map.chunkRevisions)
        assertUnchangedChunksMatch(before, beforeChunks, after, afterChunks)
    }

    func testChunkTintMatchesFrameAndPrologueChunksAreNeutral() throws {
        let content = try TestContent.publicOnly()
        let builder = FrameBuilder(content: content)
        var world = TestRig(content: content).factory.newWorld(seed: 1)
        know(&world, [GridPoint(1, 1)])
        world.clock.now = GameTime(seconds: 90 * 60)
        let frame = builder.build(world, revision: 1, previous: nil, report: nil)
        XCTAssertTrue(chunks(builder, world, frame).allSatisfy { $0.timeTint == frame.timeTint })

        var prologueContent = content
        try ContentLoader.apply(json: Data(#"""
        {"scenes":[{"id":"scene.test.prologue","style":"prologue","lines":[]}]}
        """#.utf8), to: &prologueContent)
        world.narrative.scene = SceneProgress(scene: "scene.test.prologue")
        let prologueBuilder = FrameBuilder(content: prologueContent)
        let prologueFrame = prologueBuilder.build(world, revision: 2, previous: frame, report: nil)
        XCTAssertNotNil(prologueFrame.prologue)
        XCTAssertTrue(chunks(prologueBuilder, world, prologueFrame).allSatisfy { $0.timeTint == .neutral })
    }
}
