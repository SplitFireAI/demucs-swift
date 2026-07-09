# demucs-swift

Swift SDK for [demucs-rs](https://github.com/ondeinference/demucs-rs) — on-device
music source separation (HTDemucs v4) for iOS, macOS, tvOS, and visionOS,
GPU-accelerated via Metal.

> **This repository is machine-published.** Every release of
> [demucs-rs](https://github.com/ondeinference/demucs-rs) rewrites
> `Package.swift` and `Sources/Demucs/demucs.swift` via CI. Do not edit them
> by hand — changes belong in the `demucs-ffi` crate in demucs-rs.

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/ondeinference/demucs-swift", from: "0.1.0")
]
```

## Usage

```swift
import Demucs

// 1. Sandboxed platforms (iOS/tvOS/visionOS): point the weight cache inside
//    the app container once at launch.
let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
configureCacheDir(path: caches.appendingPathComponent("demucs").path)

// 2. Download weights (84–333 MB, from HuggingFace, cached on disk).
final class DownloadHandler: DownloadProgressListener {
    func onProgress(progress: DownloadProgress) -> Bool {
        print("download \(Int(progress.fraction * 100))%")
        return true  // return false to cancel
    }
}
try await downloadModel(model: .fourStem, listener: DownloadHandler())

// 3. Load the model and pre-compile GPU shaders.
let engine = DemucsEngine()
let seconds = try await engine.loadModel(model: .fourStem)
try await engine.warmup()

// 4. Separate. Input is per-channel PCM at any sample rate (use AVFoundation
//    to decode files); output stems are stereo PCM at 44100 Hz.
final class ProgressHandler: SeparationProgressListener {
    func onProgress(progress: SeparationProgress) -> Bool {
        print("separating \(Int(progress.fraction * 100))%")
        return true  // return false to cancel
    }
}
let stems = try await separateWithProgress(
    engine: engine,
    left: leftSamples, right: rightSamples,
    sampleRate: 44100,
    listener: ProgressHandler()
)
for stem in stems {
    print(stem.kind, stem.left.count)
}

// Or without progress reporting:
let stems2 = try await engine.separate(left: leftSamples, right: rightSamples, sampleRate: 44100)
```

## Models

| Model | Case | Stems | Size |
|-------|------|-------|------|
| htdemucs | `.fourStem` | drums, bass, other, vocals | ~84 MB |
| htdemucs_6s | `.sixStem` | + guitar, piano | ~84 MB |
| htdemucs_ft | `.fineTuned(stems:)` | up to 4, best quality | ~333 MB |

Weights download from HuggingFace on demand and are cached locally
(`allModels()`, `isModelCached(model:)`, `deleteCachedModel(model:)` manage
the cache).

## License

Apache-2.0, same as demucs-rs.
