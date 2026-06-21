import XCTest
import AVFoundation
import CoreGraphics
@testable import CameraKit

// MARK: - Authorization mapping

final class CameraAuthorizationTests: XCTestCase {

    func testMapsEveryAVStatus() {
        XCTAssertEqual(CameraAuthorization(.notDetermined), .notDetermined)
        XCTAssertEqual(CameraAuthorization(.authorized), .authorized)
        XCTAssertEqual(CameraAuthorization(.denied), .denied)
        XCTAssertEqual(CameraAuthorization(.restricted), .restricted)
    }

    func testIsAuthorized() {
        XCTAssertTrue(CameraAuthorization.authorized.isAuthorized)
        XCTAssertFalse(CameraAuthorization.denied.isAuthorized)
        XCTAssertFalse(CameraAuthorization.notDetermined.isAuthorized)
    }

    func testCanRequestOnlyWhenNotDetermined() {
        XCTAssertTrue(CameraAuthorization.notDetermined.canRequest)
        XCTAssertFalse(CameraAuthorization.authorized.canRequest)
        XCTAssertFalse(CameraAuthorization.denied.canRequest)
    }

    func testRequiresSettings() {
        XCTAssertTrue(CameraAuthorization.denied.requiresSettings)
        XCTAssertTrue(CameraAuthorization.restricted.requiresSettings)
        XCTAssertFalse(CameraAuthorization.notDetermined.requiresSettings)
        XCTAssertFalse(CameraAuthorization.authorized.requiresSettings)
    }
}

// MARK: - State machine

final class CameraStateMachineTests: XCTestCase {

    func testStartsIdle() {
        XCTAssertEqual(CameraStateMachine().state, .idle)
    }

    func testNotDeterminedNeedsAuthorization() {
        var machine = CameraStateMachine()
        machine.update(authorization: .notDetermined, hasCamera: true)
        XCTAssertEqual(machine.state, .needsAuthorization)
    }

    func testDeniedAndRestrictedBecomeDenied() {
        var denied = CameraStateMachine()
        denied.update(authorization: .denied, hasCamera: true)
        XCTAssertEqual(denied.state, .denied)

        var restricted = CameraStateMachine()
        restricted.update(authorization: .restricted, hasCamera: true)
        XCTAssertEqual(restricted.state, .denied)
    }

    func testAuthorizedWithoutCameraIsUnavailable() {
        var machine = CameraStateMachine()
        machine.update(authorization: .authorized, hasCamera: false)
        XCTAssertEqual(machine.state, .unavailable)
    }

    func testAuthorizedWithCameraIsReady() {
        var machine = CameraStateMachine()
        machine.update(authorization: .authorized, hasCamera: true)
        XCTAssertEqual(machine.state, .ready)
    }

    func testStartAndStopRunning() {
        var machine = CameraStateMachine()
        machine.update(authorization: .authorized, hasCamera: true)
        machine.didStartRunning()
        XCTAssertEqual(machine.state, .running)
        XCTAssertTrue(machine.state.isRunning)
        machine.didStopRunning()
        XCTAssertEqual(machine.state, .ready)
    }

    func testStartRunningIgnoredWhenNotReady() {
        var machine = CameraStateMachine()   // idle
        machine.didStartRunning()
        XCTAssertEqual(machine.state, .idle)
    }

    func testReevaluationPreservesRunning() {
        var machine = CameraStateMachine()
        machine.update(authorization: .authorized, hasCamera: true)
        machine.didStartRunning()
        // A routine permission re-check shouldn't appear to stop the session.
        machine.update(authorization: .authorized, hasCamera: true)
        XCTAssertEqual(machine.state, .running)
    }

    func testRevokingAuthorizationWhileRunning() {
        var machine = CameraStateMachine()
        machine.update(authorization: .authorized, hasCamera: true)
        machine.didStartRunning()
        machine.update(authorization: .denied, hasCamera: true)
        XCTAssertEqual(machine.state, .denied)
    }

    func testGrantingAuthorizationTransitionsToReady() {
        var machine = CameraStateMachine()
        machine.update(authorization: .notDetermined, hasCamera: true)
        XCTAssertEqual(machine.state, .needsAuthorization)
        machine.update(authorization: .authorized, hasCamera: true)
        XCTAssertEqual(machine.state, .ready)
    }

    func testFailOverrides() {
        var machine = CameraStateMachine()
        machine.update(authorization: .authorized, hasCamera: true)
        machine.didFail("boom")
        XCTAssertEqual(machine.state, .failed("boom"))
    }
}

// MARK: - Configuration

final class CameraConfigurationTests: XCTestCase {

    func testPositionMappingAndToggle() {
        XCTAssertEqual(CameraPosition.front.avPosition, .front)
        XCTAssertEqual(CameraPosition.back.avPosition, .back)
        XCTAssertEqual(CameraPosition.front.toggled, .back)
        XCTAssertEqual(CameraPosition.back.toggled, .front)
    }

    func testQualityPresetMapping() {
        XCTAssertEqual(CameraQuality.photo.preset, .photo)
        XCTAssertEqual(CameraQuality.high.preset, .high)
        XCTAssertEqual(CameraQuality.medium.preset, .medium)
        XCTAssertEqual(CameraQuality.low.preset, .low)
    }

    func testDefaultConfiguration() {
        let config = CameraConfiguration()
        XCTAssertEqual(config.position, .back)
        XCTAssertEqual(config.quality, .high)
        XCTAssertFalse(config.enablesAudio)
        XCTAssertTrue(config.enablesPhoto)
        XCTAssertFalse(config.enablesVideo)
        XCTAssertTrue(config.enablesFrameStream)
    }

    func testPhotoAndVideoPresets() {
        XCTAssertEqual(CameraConfiguration.photo.quality, .photo)
        XCTAssertFalse(CameraConfiguration.photo.enablesVideo)

        XCTAssertTrue(CameraConfiguration.video.enablesVideo)
        XCTAssertTrue(CameraConfiguration.video.enablesAudio)
        XCTAssertFalse(CameraConfiguration.video.enablesPhoto)
    }
}

// MARK: - Capture geometry

final class CaptureGeometryTests: XCTestCase {
    private let size = CGSize(width: 200, height: 400)

    func testCenter() {
        let p = CaptureGeometry.normalizedPoint(viewPoint: CGPoint(x: 100, y: 200), viewSize: size)
        XCTAssertEqual(p.x, 0.5, accuracy: 1e-6)
        XCTAssertEqual(p.y, 0.5, accuracy: 1e-6)
    }

    func testCorners() {
        let topLeft = CaptureGeometry.normalizedPoint(viewPoint: CGPoint(x: 0, y: 0), viewSize: size)
        XCTAssertEqual(topLeft, CGPoint(x: 0, y: 0))
        let bottomRight = CaptureGeometry.normalizedPoint(viewPoint: CGPoint(x: 200, y: 400), viewSize: size)
        XCTAssertEqual(bottomRight, CGPoint(x: 1, y: 1))
    }

    func testClampsOutOfBounds() {
        let p = CaptureGeometry.normalizedPoint(viewPoint: CGPoint(x: -50, y: 800), viewSize: size)
        XCTAssertEqual(p.x, 0, accuracy: 1e-6)
        XCTAssertEqual(p.y, 1, accuracy: 1e-6)
    }

    func testZeroSizeReturnsCenter() {
        let p = CaptureGeometry.normalizedPoint(viewPoint: CGPoint(x: 10, y: 10), viewSize: .zero)
        XCTAssertEqual(p, CGPoint(x: 0.5, y: 0.5))
    }
}

// MARK: - Error descriptions

final class CameraErrorTests: XCTestCase {
    func testDescriptionsNonEmpty() {
        let errors: [CameraError] = [
            .notAuthorized(.denied), .cameraUnavailable, .cannotAddInput, .cannotAddOutput,
            .configurationFailed("x"), .captureFailed("y"), .invalidPhotoData
        ]
        for error in errors {
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true)
        }
    }
}
