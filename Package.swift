// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Kits",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DesignSystem",  targets: ["DesignSystem"]),
        .library(name: "AppFoundation", targets: ["AppFoundation"]),
        .library(name: "PaywallKit",    targets: ["PaywallKit"]),
        .library(name: "PersistenceKit",targets: ["PersistenceKit"]),
        .library(name: "SyncKit",       targets: ["SyncKit"]),
        .library(name: "SecurityKit",   targets: ["SecurityKit"]),
        .library(name: "NetworkKit",    targets: ["NetworkKit"]),
        .library(name: "CameraKit",     targets: ["CameraKit"]),
        .library(name: "RenderKit",     targets: ["RenderKit"]),
        .library(name: "ChartsKit",     targets: ["ChartsKit"]),
        .library(name: "VisionScanKit", targets: ["VisionScanKit"]),
        .library(name: "PaymentsKit",   targets: ["PaymentsKit"]),
    ],
    targets: [
        .target(name: "DesignSystem"),
        .target(name: "AppFoundation"),
        .target(name: "PaywallKit",     dependencies: ["AppFoundation"]),
        .target(name: "PersistenceKit"),
        .target(name: "SyncKit",        dependencies: ["PersistenceKit"]),
        .target(name: "SecurityKit"),
        .target(name: "NetworkKit"),
        .target(name: "CameraKit",      dependencies: ["RenderKit"]),
        .target(name: "RenderKit"),
        .target(name: "ChartsKit",      dependencies: ["RenderKit"]),
        .target(name: "VisionScanKit",  dependencies: ["CameraKit"]),
        .target(name: "PaymentsKit"),
        .testTarget(name: "DesignSystemTests",    dependencies: ["DesignSystem"]),
        .testTarget(name: "PaywallKitTests",      dependencies: ["PaywallKit"]),
        .testTarget(name: "PersistenceKitTests",  dependencies: ["PersistenceKit"]),
        .testTarget(name: "AppFoundationTests",   dependencies: ["AppFoundation"]),
    ]
)
