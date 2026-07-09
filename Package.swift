// swift-tools-version:5.9
import PackageDescription

// These two constants are rewritten automatically by the demucs-rs
// "Release SDK Swift" workflow on every release. Do not reformat them —
// the rewrite regex depends on this exact layout.
//
// For local development against a locally built framework, comment out the
// url/checksum binaryTarget below and use the path form instead:
//   .binaryTarget(name: "DemucsFramework", path: "../demucs-rs/dist/swift/DemucsFramework.xcframework"),
// (run .github/scripts/build-swift-xcframework.sh in demucs-rs first).
// Never commit the path form — CI overwrites this file on every release.
let releaseFrameworkURL =
    "https://github.com/ondeinference/demucs-rs/releases/download/swift-0.1.0/DemucsFramework.xcframework.zip"
let releaseFrameworkChecksum =
    "0000000000000000000000000000000000000000000000000000000000000000"

let package = Package(
    name: "Demucs",
    platforms: [
        .iOS(.v16),
        .macOS(.v14),
        .tvOS(.v16),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "Demucs", targets: ["Demucs"])
    ],
    targets: [
        .binaryTarget(
            name: "DemucsFramework",
            url: releaseFrameworkURL,
            checksum: releaseFrameworkChecksum
        ),
        .target(
            name: "Demucs",
            dependencies: ["DemucsFramework"],
            path: "Sources/Demucs"
        ),
    ]
)
