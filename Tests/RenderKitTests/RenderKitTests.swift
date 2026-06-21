import XCTest
import simd
import CoreGraphics
@testable import RenderKit

// MARK: - Pure colour math (headless)

final class ColorAdjustmentTests: XCTestCase {

    private func assertClose(_ a: SIMD3<Float>, _ b: SIMD3<Float>, accuracy: Float = 1e-5,
                             _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(a.z, b.z, accuracy: accuracy, message, file: file, line: line)
    }

    func testIdentityLeavesColorUnchanged() {
        let input = SIMD3<Float>(0.2, 0.4, 0.6)
        assertClose(ColorAdjustment.identity.apply(to: input), input)
    }

    func testBrightnessScales() {
        let out = ColorAdjustment(brightness: 1.5).apply(to: SIMD3<Float>(0.3, 0.3, 0.3))
        assertClose(out, SIMD3<Float>(0.45, 0.45, 0.45))
    }

    func testZeroBrightnessIsBlack() {
        let out = ColorAdjustment(brightness: 0).apply(to: SIMD3<Float>(0.7, 0.5, 0.2))
        assertClose(out, SIMD3<Float>(0, 0, 0))
    }

    func testZeroSaturationProducesGreyAtLuminance() {
        let input = SIMD3<Float>(0.8, 0.2, 0.2)
        let out = ColorAdjustment(saturation: 0).apply(to: input)
        let lum = Luma.luminance(input)
        assertClose(out, SIMD3<Float>(lum, lum, lum))
        XCTAssertEqual(out.x, out.y, accuracy: 1e-5)
        XCTAssertEqual(out.y, out.z, accuracy: 1e-5)
    }

    func testContrastAboutMidGreyLeavesGreyFixed() {
        // Mid-grey (0.5) is the contrast pivot, so it should not move.
        let out = ColorAdjustment(contrast: 2).apply(to: SIMD3<Float>(0.5, 0.5, 0.5))
        assertClose(out, SIMD3<Float>(0.5, 0.5, 0.5))
    }

    func testResultIsClamped() {
        let out = ColorAdjustment(brightness: 4).apply(to: SIMD3<Float>(0.5, 0.5, 0.5))
        assertClose(out, SIMD3<Float>(1, 1, 1))
    }
}

// MARK: - Gaussian kernel (headless)

final class GaussianKernelTests: XCTestCase {

    func testZeroRadiusIsIdentity() {
        let kernel = GaussianKernel(radius: 0)
        XCTAssertEqual(kernel.weights, [1])
        XCTAssertEqual(kernel.radius, 0)
    }

    func testNegativeRadiusClampsToIdentity() {
        XCTAssertEqual(GaussianKernel(radius: -5).weights, [1])
    }

    func testLengthIsRadiusPlusOne() {
        XCTAssertEqual(GaussianKernel(radius: 4).weights.count, 5)
    }

    func testNormalizedSumIsOne() {
        for radius in [1, 2, 4, 8, 16] {
            let kernel = GaussianKernel(radius: radius)
            XCTAssertEqual(kernel.normalizedSum, 1, accuracy: 1e-4, "radius \(radius)")
        }
    }

    func testWeightsArePositiveAndMonotonicallyDecreasing() {
        let weights = GaussianKernel(radius: 6).weights
        XCTAssertTrue(weights.allSatisfy { $0 > 0 })
        for i in 1..<weights.count {
            XCTAssertLessThan(weights[i], weights[i - 1])
        }
    }
}

// MARK: - Unsharp & blend math (headless)

final class FilterMathTests: XCTestCase {

    func testUnsharpOnFlatRegionIsNoOp() {
        XCTAssertEqual(unsharpMask(input: 0.5, blurred: 0.5, amount: 2), 0.5, accuracy: 1e-6)
    }

    func testUnsharpBoostsEdges() {
        // Where input exceeds the blurred value, sharpening pushes it higher.
        XCTAssertEqual(unsharpMask(input: 0.6, blurred: 0.4, amount: 0.5), 0.7, accuracy: 1e-6)
    }

    func testUnsharpClamps() {
        XCTAssertEqual(unsharpMask(input: 0.9, blurred: 0.1, amount: 5), 1, accuracy: 1e-6)
    }

    func testAverageBlendIsIncrementalMean() {
        // First frame passes through, second yields the mean of the two.
        let first = BlendMode.average.blend(accumulated: 0, incoming: 0.4, sampleCount: 0)
        XCTAssertEqual(first, 0.4, accuracy: 1e-6)
        let second = BlendMode.average.blend(accumulated: first, incoming: 0.8, sampleCount: 1)
        XCTAssertEqual(second, 0.6, accuracy: 1e-6)
    }

    func testLightenKeepsMax() {
        XCTAssertEqual(BlendMode.lighten.blend(accumulated: 0.4, incoming: 0.8, sampleCount: 1), 0.8)
    }

    func testAdditiveClamps() {
        XCTAssertEqual(BlendMode.additive.blend(accumulated: 0.7, incoming: 0.6, sampleCount: 1), 1)
    }

    func testScreenBrightensWithoutClipping() {
        // 1 - (1-0.5)(1-0.5) = 0.75
        XCTAssertEqual(BlendMode.screen.blend(accumulated: 0.5, incoming: 0.5, sampleCount: 1), 0.75, accuracy: 1e-6)
    }
}

// MARK: - CPU image bridging round-trip (headless)

final class ImageBridgeTests: XCTestCase {

    func testRGBA8RoundTrip() throws {
        let width = 4, height = 3
        // A deterministic opaque gradient (alpha 255 so premultiplication is a no-op).
        var bytes = [UInt8]()
        for y in 0..<height {
            for x in 0..<width {
                bytes.append(UInt8((x * 60) % 256))
                bytes.append(UInt8((y * 80) % 256))
                bytes.append(UInt8((x * y * 10) % 256))
                bytes.append(255)
            }
        }
        let image = try XCTUnwrap(ImageBridge.makeCGImage(rgba8: bytes, width: width, height: height))
        XCTAssertEqual(image.width, width)
        XCTAssertEqual(image.height, height)
        let roundTripped = try XCTUnwrap(ImageBridge.rgba8Bytes(from: image))
        XCTAssertEqual(roundTripped, bytes)
    }

    func testRejectsWrongByteCount() {
        XCTAssertNil(ImageBridge.makeCGImage(rgba8: [0, 0, 0], width: 2, height: 2))
    }
}

// MARK: - GPU tests (gated on a Metal device; skipped on CI without a GPU)

final class MetalGPUTests: XCTestCase {

    private func requireContext() throws -> MetalContext {
        try XCTSkipUnless(MetalContext.shared != nil, "No Metal device available (headless/CI)")
        return MetalContext.shared!
    }

    /// A solid-colour opaque image (equal channels → robust to any channel-order differences).
    private func solidGrey(_ value: UInt8, width: Int = 8, height: Int = 8) -> CGImage {
        var bytes = [UInt8]()
        for _ in 0..<(width * height) { bytes.append(contentsOf: [value, value, value, 255]) }
        return ImageBridge.makeCGImage(rgba8: bytes, width: width, height: height)!
    }

    private func averageRGB(of image: CGImage) -> (r: Double, g: Double, b: Double) {
        let bytes = ImageBridge.rgba8Bytes(from: image)!
        var r = 0.0, g = 0.0, b = 0.0
        let pixels = bytes.count / 4
        for i in 0..<pixels {
            r += Double(bytes[i * 4]); g += Double(bytes[i * 4 + 1]); b += Double(bytes[i * 4 + 2])
        }
        return (r / Double(pixels), g / Double(pixels), b / Double(pixels))
    }

    func testLibraryExposesAllShaders() throws {
        let context = try requireContext()
        for name in ["fullscreen_vertex", "passthrough_fragment", "color_adjust_fragment",
                     "gaussian_blur_fragment", "unsharp_fragment", "composite_fragment"] {
            XCTAssertNotNil(context.library.makeFunction(name: name), "missing \(name)")
        }
    }

    func testPassthroughPreservesColor() throws {
        let context = try requireContext()
        let output = try context.apply([PassthroughFilter()], to: solidGrey(200))
        let avg = averageRGB(of: output)
        XCTAssertEqual(avg.r, 200, accuracy: 2)
        XCTAssertEqual(avg.g, 200, accuracy: 2)
        XCTAssertEqual(avg.b, 200, accuracy: 2)
    }

    func testEmptyChainCopiesImage() throws {
        let context = try requireContext()
        let output = try context.apply([], to: solidGrey(128))
        let avg = averageRGB(of: output)
        XCTAssertEqual(avg.r, 128, accuracy: 2)
    }

    func testZeroBrightnessProducesBlack() throws {
        let context = try requireContext()
        let output = try context.apply([ColorAdjustFilter(brightness: 0)], to: solidGrey(180))
        let avg = averageRGB(of: output)
        XCTAssertEqual(avg.r, 0, accuracy: 2)
        XCTAssertEqual(avg.g, 0, accuracy: 2)
        XCTAssertEqual(avg.b, 0, accuracy: 2)
    }

    func testDesaturationProducesGrey() throws {
        let context = try requireContext()
        // Uniform coloured image; after saturation 0 all channels must converge.
        var bytes = [UInt8]()
        for _ in 0..<64 { bytes.append(contentsOf: [200, 60, 60, 255]) }
        let colored = ImageBridge.makeCGImage(rgba8: bytes, width: 8, height: 8)!
        let output = try context.apply([ColorAdjustFilter(saturation: 0)], to: colored)
        let avg = averageRGB(of: output)
        XCTAssertEqual(avg.r, avg.g, accuracy: 2)
        XCTAssertEqual(avg.g, avg.b, accuracy: 2)
    }

    func testBlurOfUniformIsUnchanged() throws {
        let context = try requireContext()
        let output = try context.apply([GaussianBlurFilter(radius: 5)], to: solidGrey(160))
        let avg = averageRGB(of: output)
        XCTAssertEqual(avg.r, 160, accuracy: 2)
    }

    func testUnsharpOfUniformIsUnchanged() throws {
        let context = try requireContext()
        let output = try context.apply([UnsharpMaskFilter(radius: 3, amount: 1.5)], to: solidGrey(120))
        let avg = averageRGB(of: output)
        XCTAssertEqual(avg.r, 120, accuracy: 2)
    }

    func testChainComposesFilters() throws {
        let context = try requireContext()
        // Brightness 0.5 then passthrough → ~half.
        let output = try context.apply([ColorAdjustFilter(brightness: 0.5), PassthroughFilter()],
                                       to: solidGrey(200))
        let avg = averageRGB(of: output)
        XCTAssertEqual(avg.r, 100, accuracy: 3)
    }

    // MARK: FrameCompositor

    private func solidTexture(_ context: MetalContext, value: UInt8) throws -> MTLTexture {
        try context.makeTexture(rgba8: [value, value, value, 255], width: 1, height: 1)
    }

    func testCompositorAveragesFrames() throws {
        let context = try requireContext()
        let compositor = try FrameCompositor(context: context, width: 1, height: 1, mode: .average)
        try compositor.add(solidTexture(context, value: 102)) // ~0.4
        try compositor.add(solidTexture(context, value: 204)) // ~0.8
        XCTAssertEqual(compositor.frameCount, 2)
        let result = compositor.resultBytes()
        XCTAssertEqual(Double(result[0]), 153, accuracy: 3) // ~0.6 * 255
    }

    func testCompositorLightenKeepsBrightest() throws {
        let context = try requireContext()
        let compositor = try FrameCompositor(context: context, width: 1, height: 1, mode: .lighten)
        try compositor.add(solidTexture(context, value: 80))
        try compositor.add(solidTexture(context, value: 200))
        try compositor.add(solidTexture(context, value: 120))
        XCTAssertEqual(Double(compositor.resultBytes()[0]), 200, accuracy: 3)
    }

    func testCompositorAdditiveClamps() throws {
        let context = try requireContext()
        let compositor = try FrameCompositor(context: context, width: 1, height: 1, mode: .additive)
        try compositor.add(solidTexture(context, value: 200))
        try compositor.add(solidTexture(context, value: 200))
        XCTAssertEqual(Double(compositor.resultBytes()[0]), 255, accuracy: 1)
    }

    func testCompositorResetClearsAccumulator() throws {
        let context = try requireContext()
        let compositor = try FrameCompositor(context: context, width: 1, height: 1, mode: .average)
        try compositor.add(solidTexture(context, value: 200))
        try compositor.reset()
        XCTAssertEqual(compositor.frameCount, 0)
        XCTAssertEqual(Double(compositor.resultBytes()[0]), 0, accuracy: 1)
    }
}
