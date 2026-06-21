# ios-kits — shared Swift Package monorepo

Reusable modules for the whole app portfolio. Each app imports only what it needs and
stays a thin shell on top of these.

## Modules
| Module | Status | Purpose |
|---|---|---|
| DesignSystem | ✅ starter | Tokens, `Theme`, `PrimaryButton`, `Card`. Override the palette per app. |
| AppFoundation | ✅ starter | Logging, review prompts, onboarding flag. |
| PaywallKit | ✅ starter | StoreKit 2 `SubscriptionManager` + reusable `PaywallView`. |
| PersistenceKit | ✅ starter | SwiftData container helper + `Repository` protocol. |
| SecurityKit | ✅ starter | Face ID gate + Keychain wrapper. |
| NetworkKit | ✅ starter | Async `APIClient` + `WebSocketClient` (AsyncStream). |
| SyncKit | 🟡 seed | Offline-first CRDT (`LWWRegister`). CloudKit transport later. |
| ChartsKit | 🟡 seed | `Candle` model; Metal renderer built with #47. |
| RenderKit | 🟡 stub | Metal shaders/filters; build with first Metal app. |
| CameraKit | 🟡 stub | AVFoundation capture; build with first camera app. |
| VisionScanKit | 🟡 stub | Vision OCR/CV; build with #11/#12. |
| PaymentsKit | 🟡 seed | `PaymentService` + `MockPaymentService`. Real Apple Pay/Tap to Pay needs a paid account. |

## Add to an app (local path dependency, no account needed)
In Xcode: **File ▸ Add Package Dependencies… ▸ Add Local…** and select this `ios-kits` folder.
Then add the product libraries you need to your app target. Or in another package:
```swift
.package(path: "../ios-kits")
```

## Testing payments without a paid Apple Developer account
PaywallKit is fully testable now:
1. In Xcode, add a **StoreKit Configuration File** (`Configuration.storekit`) with your
   products (e.g. `pro.weekly`, `pro.yearly`).
2. Scheme ▸ Edit Scheme ▸ Run ▸ Options ▸ **StoreKit Configuration** → select it.
3. Run in the simulator — purchases, restores, and entitlements work locally, no
   App Store Connect, no payment.

## Build order
DesignSystem → AppFoundation → PaywallKit → PersistenceKit → SecurityKit → NetworkKit,
then RenderKit/ChartsKit/CameraKit/VisionScanKit/PaymentsKit/SyncKit as the first app
that needs each comes up.

## Note
This is a **starter scaffold** generated to skip the blank-page step. Open it in Xcode;
let Claude Code resolve any compile nits and flesh out the 🟡 modules as you build each app.
The ✅ modules contain real, working patterns (StoreKit 2 manager, SwiftData stack,
Keychain, WebSocket stream) you can build on immediately.
