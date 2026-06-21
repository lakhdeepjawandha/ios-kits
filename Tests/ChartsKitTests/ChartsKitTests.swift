import XCTest
import simd
import CoreGraphics
import Metal
import RenderKit
@testable import ChartsKit

// MARK: - Mock data

final class MockSeriesTests: XCTestCase {
    func testDeterministic() {
        XCTAssertEqual(Candle.mockSeries(count: 20), Candle.mockSeries(count: 20))
    }

    func testCountAndChronology() {
        let candles = Candle.mockSeries(count: 50, interval: 60)
        XCTAssertEqual(candles.count, 50)
        for i in 1..<candles.count {
            XCTAssertEqual(candles[i].time.timeIntervalSince(candles[i - 1].time), 60, accuracy: 1e-6)
        }
    }

    func testOHLCInvariants() {
        for candle in Candle.mockSeries(count: 100) {
            XCTAssertGreaterThanOrEqual(candle.high, candle.open)
            XCTAssertGreaterThanOrEqual(candle.high, candle.close)
            XCTAssertLessThanOrEqual(candle.low, candle.open)
            XCTAssertLessThanOrEqual(candle.low, candle.close)
        }
    }
}

// MARK: - TickToCandleAggregator

final class AggregatorTests: XCTestCase {
    private func t(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

    func testFirstTickOpensCandle() {
        var agg = TickToCandleAggregator(timeframe: .m1)
        let opened = agg.add(price: 100, time: t(0))
        XCTAssertTrue(opened)
        XCTAssertEqual(agg.candles.count, 1)
        XCTAssertEqual(agg.latest, Candle(time: t(0), open: 100, high: 100, low: 100, close: 100))
    }

    func testSameBucketUpdatesOHLC() {
        var agg = TickToCandleAggregator(timeframe: .m1)
        agg.add(price: 100, time: t(0))
        XCTAssertFalse(agg.add(price: 105, time: t(10)))
        XCTAssertFalse(agg.add(price: 95, time: t(20)))
        XCTAssertFalse(agg.add(price: 102, time: t(59)))
        XCTAssertEqual(agg.candles.count, 1)
        XCTAssertEqual(agg.latest, Candle(time: t(0), open: 100, high: 105, low: 95, close: 102))
    }

    func testNextBucketOpensNewCandle() {
        var agg = TickToCandleAggregator(timeframe: .m1)
        agg.add(price: 100, time: t(30))
        let opened = agg.add(price: 101, time: t(61))
        XCTAssertTrue(opened)
        XCTAssertEqual(agg.candles.count, 2)
        XCTAssertEqual(agg.candles[1].time, t(60))
        XCTAssertEqual(agg.candles[1].open, 101)
    }

    func testBucketAlignmentForAllTimeframes() {
        XCTAssertEqual(TickToCandleAggregator(timeframe: .m1).bucketStart(for: t(125)), t(120))
        XCTAssertEqual(TickToCandleAggregator(timeframe: .m5).bucketStart(for: t(620)), t(600))
        XCTAssertEqual(TickToCandleAggregator(timeframe: .h1).bucketStart(for: t(3_700)), t(3_600))
        XCTAssertEqual(TickToCandleAggregator(timeframe: .d1).bucketStart(for: t(90_000)), t(86_400))
    }

    func testGapDoesNotBackfill() {
        var agg = TickToCandleAggregator(timeframe: .m1)
        agg.add(price: 100, time: t(0))
        agg.add(price: 110, time: t(180)) // 3 minutes later
        XCTAssertEqual(agg.candles.count, 2)
        XCTAssertEqual(agg.candles[1].time, t(180))
    }

    func testStaleTickIgnored() {
        var agg = TickToCandleAggregator(timeframe: .m1)
        agg.add(price: 100, time: t(120))
        XCTAssertFalse(agg.add(price: 999, time: t(30))) // older bucket
        XCTAssertEqual(agg.candles.count, 1)
        XCTAssertEqual(agg.latest?.close, 100)
    }

    func testOutOfOrderWithinBucketStillApplies() {
        var agg = TickToCandleAggregator(timeframe: .m1)
        agg.add(price: 100, time: t(50))
        agg.add(price: 120, time: t(10)) // earlier time but same bucket
        XCTAssertEqual(agg.latest?.high, 120)
        XCTAssertEqual(agg.latest?.close, 120)
    }

    func testBatchReturnsOpenedCount() {
        var agg = TickToCandleAggregator(timeframe: .m1)
        let opened = agg.add([
            Tick(price: 100, time: t(0)),
            Tick(price: 101, time: t(30)),
            Tick(price: 102, time: t(61)),
            Tick(price: 103, time: t(125)),
        ])
        XCTAssertEqual(opened, 3)
        XCTAssertEqual(agg.candles.count, 3)
    }

    func testReset() {
        var agg = TickToCandleAggregator(timeframe: .m1)
        agg.add(price: 100, time: t(0))
        agg.reset()
        XCTAssertTrue(agg.candles.isEmpty)
        XCTAssertNil(agg.latest)
    }
}

// MARK: - ChartScale

final class ChartScaleTests: XCTestCase {
    private func make() -> ChartScale {
        ChartScale(plotSize: CGSize(width: 400, height: 200),
                   visibleCandles: 50, panIndex: 10, priceMin: 100, priceMax: 200)
    }

    func testCandleWidth() {
        XCTAssertEqual(make().candleWidth, 8, accuracy: 1e-6) // 400 / 50
    }

    func testIndexRoundTrip() {
        let scale = make()
        for index in [10.0, 25.5, 59.0] {
            XCTAssertEqual(scale.index(forX: scale.x(forIndex: index)), index, accuracy: 1e-6)
        }
    }

    func testPriceRoundTrip() {
        let scale = make()
        for price in [100.0, 137.5, 200.0] {
            XCTAssertEqual(scale.price(forY: scale.y(forPrice: price)), price, accuracy: 1e-6)
        }
    }

    func testPriceTopAndBottom() {
        let scale = make()
        XCTAssertEqual(scale.y(forPrice: 200), 0, accuracy: 1e-6)   // max → top
        XCTAssertEqual(scale.y(forPrice: 100), 200, accuracy: 1e-6) // min → bottom
    }

    func testPanShiftsByWholeCandles() {
        let scale = make()
        let panned = scale.panned(byPixels: -16) // two candle-widths left → +2 index
        XCTAssertEqual(panned.panIndex, 12, accuracy: 1e-6)
    }

    func testZoomKeepsAnchorFixed() {
        let scale = make()
        let anchorX: CGFloat = 300
        let indexBefore = scale.index(forX: anchorX)
        let zoomed = scale.zoomed(factor: 2, anchorX: anchorX)
        XCTAssertEqual(zoomed.visibleCandles, 25, accuracy: 1e-6) // 50 / 2
        XCTAssertEqual(zoomed.index(forX: anchorX), indexBefore, accuracy: 1e-6)
    }

    func testZoomClampsToLimits() {
        let scale = ChartScale(plotSize: CGSize(width: 400, height: 200),
                               visibleCandles: 50, panIndex: 0, priceMin: 0, priceMax: 1,
                               minVisibleCandles: 10, maxVisibleCandles: 100)
        XCTAssertEqual(scale.zoomed(factor: 100, anchorX: 0).visibleCandles, 10) // clamped in
        XCTAssertEqual(scale.zoomed(factor: 0.01, anchorX: 0).visibleCandles, 100) // clamped out
    }

    func testPriceRangePadding() {
        let candles = [
            Candle(time: Date(timeIntervalSince1970: 0), open: 10, high: 20, low: 5, close: 15),
            Candle(time: Date(timeIntervalSince1970: 60), open: 15, high: 25, low: 10, close: 12),
        ]
        let range = ChartScale.priceRange(for: candles, padding: 0.1)
        XCTAssertNotNil(range)
        // low 5, high 25, span 20, pad 2 → (3, 27)
        XCTAssertEqual(range!.min, 3, accuracy: 1e-6)
        XCTAssertEqual(range!.max, 27, accuracy: 1e-6)
    }

    func testPriceRangeEmptyIsNil() {
        XCTAssertNil(ChartScale.priceRange(for: [Candle]()))
    }

    func testPriceRangeEqualPricesWidens() {
        let flat = [Candle(time: Date(timeIntervalSince1970: 0), open: 50, high: 50, low: 50, close: 50)]
        let range = ChartScale.priceRange(for: flat)
        XCTAssertNotNil(range)
        XCTAssertLessThan(range!.min, range!.max)
    }
}

// MARK: - AxisTicks

final class AxisTicksTests: XCTestCase {
    func testZeroToHundred() {
        XCTAssertEqual(AxisTicks.ticks(min: 0, max: 100, count: 5), [0, 20, 40, 60, 80, 100])
    }

    func testNiceNumRounding() {
        XCTAssertEqual(AxisTicks.niceNum(25, round: true), 20)
        XCTAssertEqual(AxisTicks.niceNum(25, round: false), 50)
        XCTAssertEqual(AxisTicks.niceNum(100, round: false), 100)
        XCTAssertEqual(AxisTicks.niceNum(1, round: true), 1)
    }

    func testTicksAreSortedWithinRangeAndEvenlySpaced() {
        let ticks = AxisTicks.ticks(min: 3.2, max: 17.6, count: 5)
        XCTAssertFalse(ticks.isEmpty)
        XCTAssertEqual(ticks, ticks.sorted())
        XCTAssertTrue(ticks.allSatisfy { $0 >= 3.2 && $0 <= 17.6 })
        for i in 2..<ticks.count {
            XCTAssertEqual(ticks[i] - ticks[i - 1], ticks[1] - ticks[0], accuracy: 1e-6)
        }
    }

    func testInvalidRangeIsEmpty() {
        XCTAssertTrue(AxisTicks.ticks(min: 5, max: 5).isEmpty)
        XCTAssertTrue(AxisTicks.ticks(min: 10, max: 0).isEmpty)
    }
}

// MARK: - ChartGeometry (pure)

final class ChartGeometryTests: XCTestCase {
    private func fullScale(count: Int) -> ChartScale {
        ChartScale(plotSize: CGSize(width: 200, height: 100),
                   visibleCandles: Double(count), panIndex: 0, priceMin: 0, priceMax: 100,
                   minVisibleCandles: 1)
    }

    func testNDCCorners() {
        let size = CGSize(width: 100, height: 100)
        XCTAssertEqual(ChartGeometry.ndc(CGPoint(x: 0, y: 0), in: size), SIMD2<Float>(-1, 1))
        XCTAssertEqual(ChartGeometry.ndc(CGPoint(x: 100, y: 100), in: size), SIMD2<Float>(1, -1))
        XCTAssertEqual(ChartGeometry.ndc(CGPoint(x: 50, y: 50), in: size), SIMD2<Float>(0, 0))
    }

    func testVisibleIndexRange() {
        let scale = fullScale(count: 10)
        XCTAssertEqual(ChartGeometry.visibleIndexRange(candleCount: 10, scale: scale), 0...9)
        XCTAssertNil(ChartGeometry.visibleIndexRange(candleCount: 0, scale: scale))
    }

    func testCandleVertexCountIs12PerVisibleCandle() {
        let candles = Candle.mockSeries(count: 5)
        let verts = ChartGeometry.candleVertices(candles: candles, scale: fullScale(count: 5))
        XCTAssertEqual(verts.count, 12 * 5)
    }

    func testBullishAndBearishColors() {
        let t0 = Date(timeIntervalSince1970: 0)
        let bull = [Candle(time: t0, open: 10, high: 20, low: 5, close: 18)]
        let bear = [Candle(time: t0, open: 18, high: 20, low: 5, close: 10)]
        let bullVerts = ChartGeometry.candleVertices(candles: bull, scale: fullScale(count: 1))
        let bearVerts = ChartGeometry.candleVertices(candles: bear, scale: fullScale(count: 1))
        XCTAssertEqual(bullVerts.first?.color, ChartColor.bullish.simd)
        XCTAssertEqual(bearVerts.first?.color, ChartColor.bearish.simd)
    }

    func testGridCrosshairLineBarCounts() {
        let scale = fullScale(count: 4)
        XCTAssertEqual(ChartGeometry.gridVertices(priceLevels: [10, 20, 30], scale: scale).count, 18)
        XCTAssertEqual(ChartGeometry.crosshairVertices(at: CGPoint(x: 50, y: 50), scale: scale).count, 12)
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10), CGPoint(x: 20, y: 5), CGPoint(x: 30, y: 8)]
        XCTAssertEqual(ChartGeometry.lineStripVertices(points: points, in: scale.plotSize).count, 18) // 6*(4-1)
        XCTAssertEqual(ChartGeometry.barVertices(values: [1, 2, 3, 4], scale: scale).count, 24) // 6*4
    }

    func testLineStripNeedsTwoPoints() {
        XCTAssertTrue(ChartGeometry.lineStripVertices(points: [CGPoint(x: 0, y: 0)], in: CGSize(width: 10, height: 10)).isEmpty)
    }
}

// MARK: - GPU renderer (gated on a Metal device)

final class CandlestickRendererTests: XCTestCase {
    private func requireContext() throws -> MetalContext {
        try XCTSkipUnless(MetalContext.shared != nil, "No Metal device available (headless/CI)")
        return MetalContext.shared!
    }

    func testLibraryExposesChartShaders() throws {
        _ = try requireContext()
        let renderer = try CandlestickRenderer()
        // Building a pipeline succeeds only if both shader functions exist and compile.
        XCTAssertNoThrow(try renderer.pipeline(pixelFormat: .rgba8Unorm))
    }

    func testRendersBullishCandleAsGreen() throws {
        let context = try requireContext()
        let renderer = try CandlestickRenderer()
        let size = 32

        // One bullish candle that fills the plot.
        let candle = Candle(time: Date(timeIntervalSince1970: 0), open: 0, high: 10, low: 0, close: 10)
        let scale = ChartScale(plotSize: CGSize(width: size, height: size),
                               visibleCandles: 1, panIndex: 0, priceMin: -2, priceMax: 12,
                               minVisibleCandles: 1)
        let vertices = ChartGeometry.candleVertices(candles: [candle], scale: scale)

        let texture = try context.makeColorTexture(width: size, height: size)
        let commandBuffer = context.commandQueue.makeCommandBuffer()!
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        descriptor.colorAttachments[0].storeAction = .store
        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)!
        try renderer.encode(vertices, into: encoder, pixelFormat: .rgba8Unorm)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let bytes = ImageBridge.rgba8Bytes(from: try context.makeCGImage(from: texture))!
        let center = ((size / 2) * size + (size / 2)) * 4
        let r = bytes[center], g = bytes[center + 1], b = bytes[center + 2]
        XCTAssertGreaterThan(g, 150, "centre should be the bullish green body")
        XCTAssertGreaterThan(g, r)
        XCTAssertGreaterThan(g, b)
    }
}
