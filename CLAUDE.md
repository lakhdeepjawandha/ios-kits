# iOS-Kits — Claude Code guide

## What this is
A modular Swift Package monorepo of reusable iOS modules. One repo, many library products.
Apps consume it as a local package and link only the products they need.

## Standards
- Swift 5.10, iOS 17 minimum.
- SwiftUI-first; use UIKit (via Representable) for camera/Metal/high-perf views.
- MVVM with @Observable. async/await for concurrency.
- Every public symbol gets a DocC doc-comment.
- Every module ships unit tests for its pure/testable logic.
- No external dependencies unless explicitly approved.
- Never commit secrets/API keys.

## Modules & dependency order
DesignSystem → AppFoundation → PersistenceKit → SecurityKit → NetworkKit →
PaywallKit(→AppFoundation) → RenderKit → ChartsKit(→RenderKit) →
CameraKit(→RenderKit) → VisionScanKit(→CameraKit) → PaymentsKit → SyncKit(→PersistenceKit)

## Workflow per module
1. Implement on top of the existing scaffold; keep public APIs stable.
2. Run `swift build` and `swift test`; fix all errors before finishing.
3. Commit as `Build <Module>`.

## Account-gated (keep behind protocols + mocks; needs paid Apple account to run)
PaymentsKit (Apple Pay / Tap to Pay / Wallet), SyncKit's CloudKit transport.