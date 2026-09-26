// swift-tools-version:6.2
import Foundation
import PackageDescription

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let localFrameworkPath = "DemucsFramework.xcframework"
let localFrameworkAbsolutePath = packageRoot.appendingPathComponent(localFrameworkPath).path

// Updated automatically by demucs-rs's release-sdk-swift workflow. Keep the
// layout: the workflow rewrites the quoted string on the line after each `let`.
let releaseFrameworkURL =
    "https://github.com/SplitFireAI/demucs-rs/releases/download/swift-v0.1.0/DemucsFramework.xcframework.zip"
let releaseFrameworkChecksum =
    "618b2d32ba79780310745fe4d452c8382bdd448f8efa09f06d2d518caaa6efac"

// `make macos` (or ios, tvos, visionos) drops a locally built framework next to
// this file; SwiftPM uses it when present and the release asset otherwise.
let demucsFrameworkTarget: Target
if FileManager.default.fileExists(atPath: localFrameworkAbsolutePath) {
    demucsFrameworkTarget = .binaryTarget(
        name: "DemucsFramework",
        path: localFrameworkPath
    )
} else {
    demucsFrameworkTarget = .binaryTarget(
        name: "DemucsFramework",
        url: releaseFrameworkURL,
        checksum: releaseFrameworkChecksum
    )
}

let package = Package(
    name: "Demucs",
    platforms: [
        .iOS(.v16),
        .macOS(.v14),
        .tvOS(.v16),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "Demucs", targets: ["Demucs"]),
    ],
    targets: [
        demucsFrameworkTarget,
        .target(
            name: "Demucs",
            dependencies: [.target(name: "DemucsFramework")],
            path: "Sources/Demucs",
            linkerSettings: [
                // wgpu's Metal backend.
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("IOKit", .when(platforms: [.macOS])),
                // native-tls (weight downloads) and the Rust standard library.
                .linkedFramework("CoreFoundation"),
                .linkedFramework("Foundation"),
                .linkedFramework("Security"),
            ]
        ),
        .testTarget(
            name: "DemucsTests",
            dependencies: ["Demucs"],
            path: "Tests/DemucsTests"
        ),
    ],
    // UniFFI 0.31's generated bindings predate Swift 6's region isolation
    // checks. The hand-written Demucs API is concurrency-safe; the generated
    // bridge compiles in Swift 5 language mode until UniFFI updates.
    swiftLanguageModes: [.v5]
)
