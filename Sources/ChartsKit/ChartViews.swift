#if canImport(UIKit)
import SwiftUI
import MetalKit
import RenderKit
import os

/// Colour theme shared by the chart views.
public struct ChartTheme: Sendable {
    public var bullish: ChartColor
    public var bearish: ChartColor
    public var grid: ChartColor
    public var crosshair: ChartColor
    public var line: ChartColor
    public var background: ChartColor

    public init(bullish: ChartColor = .bullish,
                bearish: ChartColor = .bearish,
                grid: ChartColor = .grid,
                crosshair: ChartColor = .crosshair,
                line: ChartColor = .line,
                background: ChartColor = ChartColor(0.07, 0.07, 0.09)) {
        self.bullish = bullish
        self.bearish = bearish
        self.grid = grid
        self.crosshair = crosshair
        self.line = line
        self.background = background
    }

    public static let dark = ChartTheme()
}

private let chartSignposter = OSSignposter(subsystem: "ChartsKit", category: "render")

// MARK: - Candlestick

/// A Metal-rendered candlestick chart with pan, pinch-zoom, a draggable crosshair readout, an
/// optional timeframe binding, and live last-candle updates targeting 60 fps.
///
/// Drawing is instrumented with `os_signpost` (subsystem `ChartsKit`, category `render`) so you can
/// profile frame time in Instruments' Points of Interest track.
///
/// ```swift
/// @State private var candles = Candle.mockSeries(count: 200)
/// @State private var timeframe: Timeframe = .m1
/// CandlestickChartView(candles: candles, timeframe: $timeframe) { hovered in
///     // update a readout label with the crosshaired candle
/// }
/// ```
public struct CandlestickChartView: UIViewRepresentable {
    private let candles: [Candle]
    private let timeframe: Binding<Timeframe>?
    private let theme: ChartTheme
    private let onCrosshair: ((Candle?) -> Void)?

    /// Create a candlestick chart.
    ///
    /// - Parameters:
    ///   - candles: Candles to display (oldest first).
    ///   - timeframe: Optional binding reflecting the active timeframe (for your own controls).
    ///   - theme: Colours. Default ``ChartTheme/dark``.
    ///   - onCrosshair: Called with the candle under the crosshair while dragging (and `nil` when
    ///     the crosshair is dismissed).
    public init(candles: [Candle],
                timeframe: Binding<Timeframe>? = nil,
                theme: ChartTheme = .dark,
                onCrosshair: ((Candle?) -> Void)? = nil) {
        self.candles = candles
        self.timeframe = timeframe
        self.theme = theme
        self.onCrosshair = onCrosshair
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(theme: theme, onCrosshair: onCrosshair)
    }

    public func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.renderer?.context.device)
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = theme.background.clearColor
        view.delegate = context.coordinator
        view.preferredFramesPerSecond = 60
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        context.coordinator.attachGestures(to: view)
        return view
    }

    public func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.update(candles: candles)
        uiView.setNeedsDisplay()
    }

    /// Drives rendering and gestures for ``CandlestickChartView``.
    public final class Coordinator: NSObject, MTKViewDelegate {
        let renderer: CandlestickRenderer?
        private let theme: ChartTheme
        private let onCrosshair: ((Candle?) -> Void)?
        private var candles: [Candle] = []
        private var scale: ChartScale?
        private var crosshair: CGPoint?

        init(theme: ChartTheme, onCrosshair: ((Candle?) -> Void)?) {
            self.renderer = try? CandlestickRenderer()
            self.theme = theme
            self.onCrosshair = onCrosshair
        }

        func update(candles: [Candle]) {
            let wasAtEnd = isScrolledToEnd
            self.candles = candles
            if var scale {
                refreshPriceRange(&scale)
                if wasAtEnd { scale.panIndex = max(0, Double(candles.count) - scale.visibleCandles) }
                self.scale = scale
            }
        }

        private var isScrolledToEnd: Bool {
            guard let scale else { return true }
            return scale.panIndex + scale.visibleCandles >= Double(candles.count) - 1
        }

        private func makeScaleIfNeeded(size: CGSize) -> ChartScale {
            if var scale {
                scale.plotSize = size
                self.scale = scale
                return scale
            }
            let visible = Double(min(max(candles.count, 1), 80))
            var scale = ChartScale(plotSize: size,
                                   visibleCandles: visible,
                                   panIndex: max(0, Double(candles.count) - visible),
                                   priceMin: 0, priceMax: 1)
            refreshPriceRange(&scale)
            self.scale = scale
            return scale
        }

        private func refreshPriceRange(_ scale: inout ChartScale) {
            guard let range = ChartGeometry.visibleIndexRange(candleCount: candles.count, scale: scale),
                  let bounds = ChartScale.priceRange(for: candles[range]) else { return }
            scale.priceMin = bounds.min
            scale.priceMax = bounds.max
        }

        // MARK: MTKViewDelegate

        public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            view.setNeedsDisplay()
        }

        public func draw(in view: MTKView) {
            guard let renderer,
                  let descriptor = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable,
                  let commandBuffer = renderer.context.commandQueue.makeCommandBuffer(),
                  let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
                return
            }
            let interval = chartSignposter.beginInterval("candlestick.draw")
            defer {
                chartSignposter.endInterval("candlestick.draw", interval)
                encoder.endEncoding()
                commandBuffer.present(drawable)
                commandBuffer.commit()
            }

            var scale = makeScaleIfNeeded(size: view.bounds.size)
            refreshPriceRange(&scale)
            self.scale = scale

            let ticks = AxisTicks.ticks(min: scale.priceMin, max: scale.priceMax, count: 5)
            var vertices = ChartGeometry.gridVertices(priceLevels: ticks, scale: scale, color: theme.grid)
            vertices += ChartGeometry.candleVertices(candles: candles, scale: scale,
                                                     bullish: theme.bullish, bearish: theme.bearish)
            if let crosshair {
                vertices += ChartGeometry.crosshairVertices(at: crosshair, scale: scale, color: theme.crosshair)
            }
            try? renderer.encode(vertices, into: encoder, pixelFormat: view.colorPixelFormat)
        }

        // MARK: Gestures

        func attachGestures(to view: MTKView) {
            view.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handlePan)))
            view.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(handlePinch)))
            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
            longPress.minimumPressDuration = 0.15
            view.addGestureRecognizer(longPress)
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view as? MTKView, var scale else { return }
            let translation = gesture.translation(in: view)
            scale = scale.panned(byPixels: translation.x)
            scale.panIndex = scale.panIndex.clamped(to: -scale.visibleCandles / 2 ... Double(max(0, candles.count)))
            self.scale = scale
            gesture.setTranslation(.zero, in: view)
            view.setNeedsDisplay()
        }

        @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let view = gesture.view as? MTKView, var scale else { return }
            let anchorX = gesture.location(in: view).x
            scale = scale.zoomed(factor: gesture.scale, anchorX: anchorX)
            self.scale = scale
            gesture.scale = 1
            view.setNeedsDisplay()
        }

        @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard let view = gesture.view as? MTKView, let scale else { return }
            switch gesture.state {
            case .began, .changed:
                let point = gesture.location(in: view)
                crosshair = point
                let index = Int(scale.index(forX: point.x).rounded())
                onCrosshair?(candles.indices.contains(index) ? candles[index] : nil)
            default:
                crosshair = nil
                onCrosshair?(nil)
            }
            view.setNeedsDisplay()
        }
    }
}

// MARK: - Line

/// A Metal-rendered line chart over a series of values, reusing the same context and pipeline.
public struct LineChartView: UIViewRepresentable {
    private let values: [Double]
    private let theme: ChartTheme

    /// Create a line chart from raw values.
    public init(values: [Double], theme: ChartTheme = .dark) {
        self.values = values
        self.theme = theme
    }

    /// Create a line chart from candle close prices.
    public init(candles: [Candle], theme: ChartTheme = .dark) {
        self.init(values: candles.map(\.close), theme: theme)
    }

    public func makeCoordinator() -> Coordinator { Coordinator(theme: theme) }

    public func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.renderer?.context.device)
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = theme.background.clearColor
        view.delegate = context.coordinator
        view.preferredFramesPerSecond = 60
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        return view
    }

    public func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.values = values
        uiView.setNeedsDisplay()
    }

    /// Drives rendering for ``LineChartView``.
    public final class Coordinator: NSObject, MTKViewDelegate {
        let renderer: CandlestickRenderer?
        private let theme: ChartTheme
        var values: [Double] = []

        init(theme: ChartTheme) {
            self.renderer = try? CandlestickRenderer()
            self.theme = theme
        }

        public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { view.setNeedsDisplay() }

        public func draw(in view: MTKView) {
            guard let renderer, !values.isEmpty,
                  let descriptor = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable,
                  let commandBuffer = renderer.context.commandQueue.makeCommandBuffer(),
                  let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
            let interval = chartSignposter.beginInterval("line.draw")
            defer {
                chartSignposter.endInterval("line.draw", interval)
                encoder.endEncoding(); commandBuffer.present(drawable); commandBuffer.commit()
            }

            let size = view.bounds.size
            let lo = values.min() ?? 0, hi = values.max() ?? 1
            let pad = (hi - lo) * 0.05 + 0.0001
            let scale = ChartScale(plotSize: size, visibleCandles: Double(values.count),
                                   panIndex: 0, priceMin: lo - pad, priceMax: hi + pad)
            let points = values.indices.map { CGPoint(x: scale.x(forIndex: Double($0)), y: scale.y(forPrice: values[$0])) }

            let ticks = AxisTicks.ticks(min: scale.priceMin, max: scale.priceMax, count: 5)
            var vertices = ChartGeometry.gridVertices(priceLevels: ticks, scale: scale, color: theme.grid)
            vertices += ChartGeometry.lineStripVertices(points: points, in: size, color: theme.line)
            try? renderer.encode(vertices, into: encoder, pixelFormat: view.colorPixelFormat)
        }
    }
}

// MARK: - Bar

/// A Metal-rendered bar chart over a series of values, reusing the same context and pipeline.
public struct BarChartView: UIViewRepresentable {
    private let values: [Double]
    private let theme: ChartTheme

    /// Create a bar chart from raw values (bars grow from `0`).
    public init(values: [Double], theme: ChartTheme = .dark) {
        self.values = values
        self.theme = theme
    }

    public func makeCoordinator() -> Coordinator { Coordinator(theme: theme) }

    public func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.renderer?.context.device)
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = theme.background.clearColor
        view.delegate = context.coordinator
        view.preferredFramesPerSecond = 60
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        return view
    }

    public func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.values = values
        uiView.setNeedsDisplay()
    }

    /// Drives rendering for ``BarChartView``.
    public final class Coordinator: NSObject, MTKViewDelegate {
        let renderer: CandlestickRenderer?
        private let theme: ChartTheme
        var values: [Double] = []

        init(theme: ChartTheme) {
            self.renderer = try? CandlestickRenderer()
            self.theme = theme
        }

        public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { view.setNeedsDisplay() }

        public func draw(in view: MTKView) {
            guard let renderer, !values.isEmpty,
                  let descriptor = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable,
                  let commandBuffer = renderer.context.commandQueue.makeCommandBuffer(),
                  let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
            let interval = chartSignposter.beginInterval("bar.draw")
            defer {
                chartSignposter.endInterval("bar.draw", interval)
                encoder.endEncoding(); commandBuffer.present(drawable); commandBuffer.commit()
            }

            let size = view.bounds.size
            let hi = max(values.max() ?? 1, 0)
            let scale = ChartScale(plotSize: size, visibleCandles: Double(values.count),
                                   panIndex: 0, priceMin: 0, priceMax: hi * 1.05 + 0.0001)
            let vertices = ChartGeometry.barVertices(values: values, scale: scale, baseline: 0, color: theme.line)
            try? renderer.encode(vertices, into: encoder, pixelFormat: view.colorPixelFormat)
        }
    }
}

private extension ChartColor {
    var clearColor: MTLClearColor { MTLClearColor(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a)) }
}

// MARK: - Preview

#Preview("Candlestick") {
    CandlestickChartView(candles: Candle.mockSeries(count: 120))
        .frame(height: 320)
        .padding()
}

#Preview("Line") {
    LineChartView(candles: Candle.mockSeries(count: 120))
        .frame(height: 240)
        .padding()
}

#Preview("Bar") {
    BarChartView(values: Candle.mockSeries(count: 40).map { $0.high - $0.low })
        .frame(height: 240)
        .padding()
}
#endif
