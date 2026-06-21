# Kits — a modular iOS Swift Package monorepo

[![CI](https://github.com/lakhdeepjawandha/ios-kits/actions/workflows/ci.yml/badge.svg)](https://github.com/lakhdeepjawandha/ios-kits/actions/workflows/ci.yml)
[![Swift 5.10](https://img.shields.io/badge/Swift-5.10-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/platforms-iOS%2017%20%7C%20macOS%2014-blue.svg)](#)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**Kits** is one Swift package that ships many focused library products — design system, networking,
persistence, security, payments, on-device vision, Metal rendering, charts, and CRDT sync. Apps add
it as a local package and link only the products they need, staying thin shells on top of reusable,
**tested** building blocks.

Everything here builds and tests **without a paid Apple Developer account**. Features that ultimately
need entitlements (Apple Pay, Tap to Pay, Wallet, CloudKit) are kept behind protocols with working
mocks, so apps compile and demo in the sandbox today and swap in the real transport later.

## Modules

| Product | Purpose |
|---|---|
| **DesignSystem** | Design tokens (`DS` spacing/radius/type), a per-app `Theme` palette, and SwiftUI components (buttons, cards, banners, list rows, metric cards). |
| **AppFoundation** | Cross-cutting utilities: `Logger.app`, analytics protocol, AUD/percent/compact/relative-date formatters, haptics, feature flags, async `Debouncer`/`Throttler`. |
| **PersistenceKit** | SwiftData `ModelContainer` helpers, a generic `Repository` protocol + SwiftData implementation, a `KeyValueStore`, and preview helpers. |
| **SecurityKit** | Face ID / passcode gate, a throwing `Keychain` (Codable values, configurable accessibility, biometry-gated items), and an `AppLockManager` foreground lock. |
| **NetworkKit** | Async `APIClient` with a `Request` builder, typed `APIError`, retry + exponential backoff; a URLProtocol-driven `MockAPIClient` + fixtures; a `WebSocketClient` with auto-reconnect, ping/pong, and typed `AsyncStream`. |
| **PaywallKit** | StoreKit 2 `SubscriptionManager` (trial/active/expired status, intro-offer eligibility), a configurable `PaywallView`, a `.requiresPro` gate, and a bundled `Configuration.storekit`. |
| **RenderKit** | Metal toolkit: `MetalContext`, `RenderPass`, image filters (passthrough / brightness-contrast-saturation / gaussian blur / unsharp), CGImage⇄CIImage⇄texture bridging, a `FrameCompositor`, and a SwiftUI `MetalView`. |
| **ChartsKit** | Metal candlestick / line / bar charts: a pure `TickToCandleAggregator`, viewport/scaling math, nice-number axes, and `MTKView`-backed SwiftUI views with pan/zoom/crosshair. |
| **CameraKit** | AVFoundation capture: an `@Observable` `CaptureController` (permissions, torch, focus, front/back, photo + video, `AsyncStream<CVPixelBuffer>`), a low-latency Metal preview, and a `CameraView`. |
| **VisionScanKit** | On-device OCR (`OCRService` + `ReceiptParser` amount/date extraction), `DocumentScanner` (edge detection + perspective correction), a Core ML `ImageClassifier` seam, and a person `Segmenter`. |
| **PaymentsKit** | Apple Pay (request builder + result mapper), Tap to Pay on iPhone, and Wallet pass assembly — all behind protocols with mocks; real flows need entitlements (documented in code). |
| **SyncKit** | Offline-first CRDTs (`LWWRegister`, `ORSet`, `MergeableDocument`) with order-independent merge convergence, a `SyncTransport` protocol + in-memory `MockTransport`, and a documented `CloudKitTransport` skeleton. |

## Quick start

Add it as a **local package** and link the products you need.

In Xcode: **File ▸ Add Package Dependencies… ▸ Add Local…** and select this `ios-kits` folder, then
add the library products (e.g. `DesignSystem`, `NetworkKit`) to your app target.

Or from another package's `Package.swift`:

```swift
dependencies: [
    .package(path: "../ios-kits"),
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "DesignSystem", package: "Kits"),
        .product(name: "NetworkKit", package: "Kits"),
    ]),
]
```

Pin a tagged release instead of a path when consuming over Git:

```swift
.package(url: "https://github.com/lakhdeepjawandha/ios-kits.git", from: "0.1.0"),
```

Build and test the whole package:

```sh
swift build
swift test
```

## Testing payments without a paid account

PaywallKit is fully exercisable on the Simulator using a **StoreKit configuration file**:

1. PaywallKit ships a sample `Configuration.storekit` (products `pro.weekly` with a 1-week free
   trial, and `pro.yearly`). Reference it from your app target, or add your own.
2. In Xcode: **Product ▸ Scheme ▸ Edit Scheme… ▸ Run ▸ Options ▸ StoreKit Configuration** → select it.
3. Run in the Simulator — `Product.products(for:)`, purchases, restores, and entitlements all work
   locally. No App Store Connect, no merchant ID, no charge.

The same philosophy applies elsewhere: `MockAPIClient`, `MockPaymentProcessor`, `MockApplePayService`,
`MockTapToPayService`, `MockWalletPassProvider`, and `MockTransport` let you build and demo entire
flows before any account or hardware is involved.

## Architecture

**Why a modular SPM monorepo.** One repository, many library products, with an explicit dependency
graph:

```
DesignSystem   AppFoundation   PersistenceKit
                   │                │
   PaywallKit ◄────┘             SyncKit

   SecurityKit   NetworkKit   PaymentsKit

   RenderKit ──► ChartsKit
       └────────► CameraKit ──► VisionScanKit
```

- **Link only what you need.** An app that's just a paywall pulls in `PaywallKit` (+ its deps) and
  nothing else — smaller builds, clearer surface area.
- **Enforced boundaries.** Cross-module use must go through a declared dependency and a public API,
  so layering stays honest and refactors stay local.
- **Testable core, deferred I/O.** Hardware/account/network concerns sit behind protocols; the pure
  logic (CRDT merges, OCR parsing, chart math, retry/backoff, color math) is unit-tested headlessly,
  so CI is green on a GPU-less, account-less runner.
- **One toolchain, one test suite.** `swift test` runs every module's tests together; CI runs the
  same command on every push and PR.

Conventions: Swift 5.10, iOS 17 / macOS 14 minimum, SwiftUI-first with `@Observable`, `async/await`,
DocC comments on public symbols, and no external dependencies. Modules whose UI is UIKit-bound
(camera/Metal previews) are guarded with `#if canImport(UIKit)` so the package still builds and tests
on the macOS host.

## Versioning

This package follows **[Semantic Versioning](https://semver.org)**. While `0.x`, the API is
stabilising: **minor** releases (`0.1 → 0.2`) may include breaking changes; **patch** releases
(`0.1.0 → 0.1.1`) are additive or fixes only. From `1.0.0` onward, breaking changes bump the
**major**. Pin with `from: "0.1.0"` and review release notes before bumping the minor.

Current release: **0.1.0** — first cohesive cut with all twelve modules implemented and tested.

## License

[MIT](LICENSE) © Lakhdeep
