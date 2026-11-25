import Foundation
import XCTest
import PomodoroCore

final class PomodoroCoreTests: XCTestCase {
    func testDrawStaysWithinBounds() {
        for steepness in [0.0, 1e-12, 0.5, 2, 50, 100, 1_000] {
            let sampler = SessionSampler(minMinutes: 10, maxMinutes: 30, steepness: steepness)
            for step in 0..<1_000 {
                let seconds = sampler.draw(u: Double(step) / 1_000)
                XCTAssertGreaterThanOrEqual(seconds, 10 * 60)
                XCTAssertLessThanOrEqual(seconds, 30 * 60)
            }
            XCTAssertEqual(sampler.draw(u: 0), 10 * 60)
            XCTAssertLessThanOrEqual(sampler.draw(u: Double(1).nextDown), 30 * 60)
        }
    }

    func testZeroSteepnessIsUniform() {
        let sampler = SessionSampler(minMinutes: 10, maxMinutes: 30, steepness: 0)
        XCTAssertEqual(sampler.draw(u: 0.5), 20 * 60, accuracy: 1e-9)
        XCTAssertEqual(sampler.draw(u: 0.25), 15 * 60, accuracy: 1e-9)
    }

    func testPositiveSteepnessHasMedianAboveMidpoint() {
        let sampler = SessionSampler()
        XCTAssertGreaterThan(sampler.draw(u: 0.5), 20 * 60)
        let x = (sampler.draw(u: 0.5) / 60 - 10) / 20
        XCTAssertEqual(expm1(2 * x) / expm1(2), 0.5, accuracy: 1e-12)
    }

    func testMaximumAtOrBelowMinimumReturnsMaximum() {
        for maximum in [5.0, 10] {
            let sampler = SessionSampler(minMinutes: 10, maxMinutes: maximum)
            for u in [0.0, 0.5, Double(1).nextDown] {
                XCTAssertEqual(sampler.draw(u: u), maximum * 60)
            }
        }
    }

    func testBreakPolicyClampsAndRoundsToWholeMinutes() {
        XCTAssertEqual(BreakPolicy.breakDuration(worked: 5 * 60), 3 * 60)
        XCTAssertEqual(BreakPolicy.breakDuration(worked: 30 * 60), 6 * 60)
        XCTAssertEqual(BreakPolicy.breakDuration(worked: 120 * 60), 10 * 60)
        XCTAssertEqual(BreakPolicy.breakDuration(worked: 28 * 60), 6 * 60)
        XCTAssertEqual(BreakPolicy.breakDuration(worked: 26 * 60), 5 * 60)
    }

    func testSessionLogRoundTripAndSkipsMalformedLine() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("sessions.jsonl")
        let log = SessionLog(fileURL: url)
        XCTAssertEqual(try log.readAll(), [])
        let first = SessionRecord(
            start: Date(timeIntervalSince1970: 1_700_000_000),
            maxMinutes: 30, minMinutes: 10, steepness: 2,
            plannedSeconds: 1_500, workedSeconds: 1_500,
            endedBy: "alarm", focusRating: 4, breakSeconds: 300, negotiated: false
        )
        var second = first
        second.start = first.start.addingTimeInterval(3_600)
        second.workedSeconds = 600
        second.endedBy = "stopped"
        second.focusRating = nil
        second.breakSeconds = 0

        try log.append(first)
        let firstLine = try Data(contentsOf: url)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: firstLine) as? [String: Any])
        XCTAssertEqual(json["start"] as? String, "2023-11-14T22:13:20Z")

        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("malformed JSON\n{\"start\":false}\n".utf8))
        try handle.close()
        try log.append(second)

        XCTAssertEqual(try SessionLog(fileURL: url).readAll(), [first, second])
        XCTAssertTrue(try Data(contentsOf: url).starts(with: firstLine))
    }
}
