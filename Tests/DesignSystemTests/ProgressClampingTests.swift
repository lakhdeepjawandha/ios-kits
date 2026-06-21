import XCTest
import SwiftUI
@testable import DesignSystem

// MARK: - Clamp helper tests

final class ProgressClampTests: XCTestCase {

    func testClampBelowRange() {
        XCTAssertEqual(DSProgress.clamp(-0.5), 0)
        XCTAssertEqual(DSProgress.clamp(-1000), 0)
    }

    func testClampAboveRange() {
        XCTAssertEqual(DSProgress.clamp(1.5), 1)
        XCTAssertEqual(DSProgress.clamp(1000), 1)
    }

    func testClampWithinRangeIsUnchanged() {
        XCTAssertEqual(DSProgress.clamp(0), 0)
        XCTAssertEqual(DSProgress.clamp(0.42), 0.42, accuracy: 0.0001)
        XCTAssertEqual(DSProgress.clamp(1), 1)
    }

    func testClampNonFiniteCollapsesToZero() {
        XCTAssertEqual(DSProgress.clamp(.nan), 0)
        XCTAssertEqual(DSProgress.clamp(.infinity), 0)
        XCTAssertEqual(DSProgress.clamp(-.infinity), 0)
    }
}

// MARK: - View-level clamping

final class ProgressIndicatorClampTests: XCTestCase {

    func testProgressBarClampsExposedValue() {
        XCTAssertEqual(ProgressBar(progress: 1.4).clampedProgress, 1)
        XCTAssertEqual(ProgressBar(progress: -0.3).clampedProgress, 0)
        XCTAssertEqual(ProgressBar(progress: 0.5).clampedProgress, 0.5, accuracy: 0.0001)
    }

    func testCircularProgressClampsExposedValue() {
        XCTAssertEqual(CircularProgress(progress: 2.0).clampedProgress, 1)
        XCTAssertEqual(CircularProgress(progress: -5).clampedProgress, 0)
        XCTAssertEqual(CircularProgress(progress: 0.25).clampedProgress, 0.25, accuracy: 0.0001)
    }

    func testProgressIndicatorsBuild() {
        _ = ProgressBar(progress: 0.3).body
        _ = ProgressBar(progress: 1.4, height: 12).body
        _ = CircularProgress(progress: 0.6).body
        _ = CircularProgress(progress: 1.4, lineWidth: 10, size: 72).body
    }
}
