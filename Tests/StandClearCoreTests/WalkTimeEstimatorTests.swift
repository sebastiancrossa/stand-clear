import StandClearCore
import XCTest

final class WalkTimeEstimatorTests: XCTestCase {
    func testEstimateAppliesGridCorrectionAndPlatformBuffer() {
        // 150 m straight-line at 1.5 m/s with 4/π correction:
        // walking = ceil(150 * 4/π / 1.5) = ceil(127.32) = 128, plus 75 buffer = 203.
        let seconds = WalkTimeEstimator.estimateSeconds(
            straightLineMeters: 150,
            pace: .average,
            platformBufferSeconds: 75
        )
        XCTAssertEqual(seconds, 203)
    }

    func testBriskPaceIsFasterThanSlow() {
        let slow = WalkTimeEstimator.estimateSeconds(
            straightLineMeters: 400,
            pace: .slow,
            platformBufferSeconds: 75
        )
        let brisk = WalkTimeEstimator.estimateSeconds(
            straightLineMeters: 400,
            pace: .brisk,
            platformBufferSeconds: 75
        )
        XCTAssertGreaterThan(slow, brisk)
    }

    func testStationOverrideReplacesEstimate() {
        let seconds = WalkTimeEstimator.resolveSeconds(
            straightLineMeters: 1_000,
            pace: .average,
            platformBufferSeconds: 75,
            stationOverrideSeconds: 180
        )
        XCTAssertEqual(seconds, 180)
    }

    func testClassifyTooLateAtExactWalkTime() {
        XCTAssertEqual(
            WalkTimeEstimator.classify(etaSeconds: 300, walkSeconds: 300),
            .tooLate
        )
    }

    func testClassifyLeaveNowJustAboveWalkTime() {
        XCTAssertEqual(
            WalkTimeEstimator.classify(etaSeconds: 301, walkSeconds: 300),
            .leaveNow
        )
    }

    func testClassifyLeaveNowAtExactWalkPlusSlack() {
        XCTAssertEqual(
            WalkTimeEstimator.classify(etaSeconds: 360, walkSeconds: 300),
            .leaveNow
        )
    }

    func testClassifyComfortableJustAboveWalkPlusSlack() {
        XCTAssertEqual(
            WalkTimeEstimator.classify(etaSeconds: 361, walkSeconds: 300),
            .comfortable
        )
    }

    func testCatchableExcludesTooLate() {
        XCTAssertTrue(Reachability.comfortable.isCatchable)
        XCTAssertTrue(Reachability.leaveNow.isCatchable)
        XCTAssertFalse(Reachability.tooLate.isCatchable)
    }
}
