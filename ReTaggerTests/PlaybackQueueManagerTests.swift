//
//  PlaybackQueueManagerTests.swift
//  ReTaggerTests
//

import XCTest
@testable import ReTagger

@MainActor
final class PlaybackQueueManagerTests: XCTestCase {

    func testSequentialAdvanceAndCompletion() {
        let items = makeSampleItems(count: 3)
        let manager = PlaybackQueueManager(order: .sequential)

        manager.load(queue: items, startAt: items[0], order: .sequential)

        XCTAssertEqual(manager.currentTrack()?.id, items[0].id)

        let nextOne = manager.advance()
        XCTAssertEqual(nextOne?.id, items[1].id)
        XCTAssertEqual(manager.currentTrack()?.id, items[1].id)

        let nextTwo = manager.advance()
        XCTAssertEqual(nextTwo?.id, items[2].id)
        XCTAssertEqual(manager.currentTrack()?.id, items[2].id)

        let end = manager.advance()
        XCTAssertNil(end)
        XCTAssertNil(manager.currentTrack())
    }

    func testHistoryAllowsRetreat() {
        let items = makeSampleItems(count: 3)
        let manager = PlaybackQueueManager(order: .sequential)
        manager.load(queue: items, startAt: items[0], order: .sequential)

        _ = manager.advance()
        XCTAssertEqual(manager.currentTrack()?.id, items[1].id)

        let previous = manager.retreat()
        XCTAssertEqual(previous?.id, items[0].id)
        XCTAssertEqual(manager.currentTrack()?.id, items[0].id)
    }

    func testShuffleKeepsCurrentTrackAtFront() {
        let items = makeSampleItems(count: 5)
        let manager = PlaybackQueueManager(order: .shuffle)
        manager.load(queue: items, startAt: items[2], order: .shuffle)

        let shuffledQueue = manager.queueSnapshot()
        XCTAssertEqual(shuffledQueue.first?.id, items[2].id)
        XCTAssertEqual(manager.currentTrack()?.id, items[2].id)

        manager.setOrder(.sequential)
        XCTAssertEqual(manager.currentTrack()?.id, items[2].id)
        XCTAssertEqual(manager.queueSnapshot().count, items.count)
    }

    func testRemovingCurrentTrackAdvancesToNext() {
        let items = makeSampleItems(count: 3)
        let manager = PlaybackQueueManager(order: .sequential)
        manager.load(queue: items, startAt: items[0], order: .sequential)

        _ = manager.advance()
        XCTAssertEqual(manager.currentTrack()?.id, items[1].id)

        let result = manager.remove(items[1])
        switch result {
        case .currentChanged(let newTrack):
            XCTAssertEqual(newTrack?.id, items[2].id)
        default:
            XCTFail("Expected currentChanged result")
        }
        XCTAssertEqual(manager.currentTrack()?.id, items[2].id)
    }

    // MARK: - Helpers

    private func makeSampleItems(count: Int) -> [AudioMetadata] {
        (0..<count).map { index in
            AudioMetadata(
                filePath: URL(fileURLWithPath: "/tmp/sample\(index).mp3"),
                fileName: "sample\(index).mp3",
                originalTitle: "Track \(index)",
                originalArtist: "Artist \(index)"
            )
        }
    }
}
