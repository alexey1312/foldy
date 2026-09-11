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
    dependencies: [
        // Sparkle ships its framework as a binary target; Scripts/bundle.sh embeds it in the app.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6"),
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
            dependencies: [
                "FoldyCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ServiceManagement"),
                // Sparkle.framework lives in Foldy.app/Contents/Frameworks (see Scripts/bundle.sh).
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
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
