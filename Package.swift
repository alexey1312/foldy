// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Foldy",
    platforms: [
        // ScreenCaptureKit, MenuBarExtra, SettingsLink, @Observable: Sonoma is the floor.
        .macOS(.v14),
    ],
    products: [
        .library(name: "FoldyCore", targets: ["FoldyCore"]),
        .executable(name: "Foldy", targets: ["Foldy"]),
        .executable(name: "foldy-snapshot", targets: ["FoldySnapshot"]),
    ],
    targets: [
        // Everything that does not need a window: the lid sensor, the display capture,
        // the Metal fold renderer, the 3D MacBook preview scene, the click sound.
        .target(
            name: "FoldyCore",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreText"),
            ]
        ),
        // The menu bar app: overlay window, settings, menu.
        .executableTarget(
            name: "Foldy",
            dependencies: ["FoldyCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        // Renders the fold (or the whole MacBook preview) to a PNG without a window.
        // Used for README images and for checking the shaders on a Mac without a lid.
        .executableTarget(
            name: "FoldySnapshot",
            dependencies: ["FoldyCore"]
        ),
        .testTarget(
            name: "FoldyCoreTests",
            dependencies: ["FoldyCore"]
        ),
    ]
)
