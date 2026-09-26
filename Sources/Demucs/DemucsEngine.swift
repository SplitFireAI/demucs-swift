import Foundation

/// One source the models can separate out of a mix.
public enum StemKind: String, Sendable, CaseIterable {
    case drums
    case bass
    case other
    case vocals
    case guitar
    case piano
}

/// Which HTDemucs variant to download or load.
public enum DemucsModel: Sendable, Hashable {
    /// htdemucs: drums, bass, other, vocals. ~84 MB.
    case fourStem

    /// htdemucs_6s: adds guitar and piano. ~84 MB.
    case sixStem

    /// htdemucs_ft: one fine-tuned sub-model per stem, best quality. ~333 MB.
    ///
    /// Only drums, bass, other and vocals are available. Each requested stem
    /// runs its own sub-model, so asking for fewer is proportionally faster.
    /// Every selection shares the same downloaded weights.
    case fineTuned(stems: [StemKind])

    /// The fine-tuned model with all four of its stems.
    public static let fineTunedAll = DemucsModel.fineTuned(stems: [.drums, .bass, .other, .vocals])
}

public struct DemucsModelInfo: Sendable, Hashable, Identifiable {
    public let model: DemucsModel
    /// The model's upstream name, such as `htdemucs`.
    public let id: String
    public let label: String
    public let description: String
    public let sizeMB: UInt32
    public let stems: [StemKind]
}

/// A separated source at the input sample rate, the same length as the input.
public struct Stem: Sendable, Equatable {
    public let kind: StemKind
    public let left: [Float]
    public let right: [Float]
}

public struct DownloadProgress: Sendable, Equatable {
    public let downloadedBytes: UInt64
    /// From the server's `Content-Length`, or the model's nominal size.
    public let totalBytes: UInt64
    public let fraction: Double
}

public struct SeparationProgress: Sendable, Equatable {
    public let fraction: Double
    public let chunkIndex: UInt64
    public let totalChunks: UInt64
}

public enum DemucsError: Error, Sendable, Equatable, LocalizedError {
    /// The task was cancelled, or a progress handler asked to stop.
    case cancelled
    /// `separate` or `warmup` was called before `load`.
    case notLoaded
    /// `load` was called before the model's weights were downloaded.
    case notDownloaded(modelID: String)
    case invalidInput(String)
    case downloadFailed(String)
    case io(String)
    case inferenceFailed(String)

    public var errorDescription: String? {
        switch self {
        case .cancelled: "The operation was cancelled."
        case .notLoaded: "No model is loaded."
        case .notDownloaded(let id): "Model \(id) has not been downloaded."
        case .invalidInput(let reason): reason
        case .downloadFailed(let reason): "Download failed: \(reason)"
        case .io(let reason): "File error: \(reason)"
        case .inferenceFailed(let reason): reason
        }
    }
}

/// On-device music source separation (HTDemucs v4), GPU-accelerated through
/// Metal.
///
/// An engine holds at most one loaded model. Loading, warming up and
/// separating on one engine run one at a time; create another engine to run
/// a second model side by side, memory permitting.
///
/// ```swift
/// try await DemucsEngine.download(.fourStem)
/// let engine = DemucsEngine()
/// try await engine.load(.fourStem)
/// let stems = try await engine.separate(left: left, right: right, sampleRate: 44_100)
/// ```
public actor DemucsEngine {
    private nonisolated let core: FfiDemucsEngine

    public init() {
        core = FfiDemucsEngine()
    }

    // MARK: Model files

    /// Sets where model weights are stored. Call once at launch, before any
    /// other Demucs call; sandboxed apps should pass a directory inside their
    /// container, such as one under Caches. Without it, weights go to the
    /// platform cache directory under `demucs-rs/`.
    public static func configureCacheDirectory(_ url: URL) {
        configureCacheDir(path: url.path)
    }

    public static var models: [DemucsModelInfo] {
        allModels().map(\.swift)
    }

    public static func info(for model: DemucsModel) -> DemucsModelInfo {
        modelMetadata(model: model.ffi).swift
    }

    public static func isDownloaded(_ model: DemucsModel) -> Bool {
        isModelCached(model: model.ffi)
    }

    /// The downloaded weights file, or `nil` if it is not on disk.
    public static func downloadedFileURL(for model: DemucsModel) -> URL? {
        cachedModelPath(model: model.ffi).map { URL(fileURLWithPath: $0) }
    }

    /// Removes the downloaded weights. Returns `false` if there was nothing
    /// to remove.
    @discardableResult
    public static func deleteDownload(_ model: DemucsModel) -> Bool {
        deleteCachedModel(model: model.ffi)
    }

    /// Downloads the model's weights from Hugging Face. Returns straight away
    /// if they are already downloaded. Cancel the calling task to stop; a
    /// partial download is discarded.
    ///
    /// `progress` is called on a background thread.
    public static func download(
        _ model: DemucsModel,
        progress: (@Sendable (DownloadProgress) -> Void)? = nil
    ) async throws {
        let listener = DownloadListener(handler: progress)
        try await withTaskCancellationHandler {
            try await translatingErrors {
                try await downloadModel(model: model.ffi, listener: listener)
            }
        } onCancel: {
            listener.cancel()
        }
    }

    // MARK: Loading

    /// Loads a downloaded model, replacing the current one. Returns the load
    /// time in seconds.
    @discardableResult
    public func load(_ model: DemucsModel) async throws -> Double {
        try await translatingErrors {
            try await core.loadModel(model: model.ffi)
        }
    }

    /// Runs a dummy separation so the first real one does not pay for GPU
    /// shader compilation. Worth calling once after `load`, off the critical
    /// path.
    public func warmup() async throws {
        try await translatingErrors {
            try await core.warmup()
        }
    }

    /// Frees the loaded model. Returns `false` if nothing was loaded.
    @discardableResult
    public func unload() async -> Bool {
        await core.unloadModel()
    }

    public nonisolated var isLoaded: Bool {
        core.isLoaded()
    }

    public nonisolated var loadedModel: DemucsModel? {
        core.loadedModel()?.swift
    }

    // MARK: Separation

    /// Separates stereo PCM at any sample rate into the loaded model's stems.
    ///
    /// Both channels must have the same, non-zero length. Audio is processed
    /// in chunks of about 7.8 seconds; cancelling the calling task stops at
    /// the next chunk boundary. `progress` is called on a background thread.
    public func separate(
        left: [Float],
        right: [Float],
        sampleRate: UInt32,
        progress: (@Sendable (SeparationProgress) -> Void)? = nil
    ) async throws -> [Stem] {
        let listener = SeparationListener(handler: progress)
        let stems = try await withTaskCancellationHandler {
            try await translatingErrors {
                try await core.separate(
                    left: left,
                    right: right,
                    sampleRate: sampleRate,
                    listener: listener
                )
            }
        } onCancel: {
            listener.cancel()
        }
        return stems.map(\.swift)
    }

    /// Separates mono PCM. The stems come back stereo with identical channels.
    public func separate(
        mono samples: [Float],
        sampleRate: UInt32,
        progress: (@Sendable (SeparationProgress) -> Void)? = nil
    ) async throws -> [Stem] {
        try await separate(left: samples, right: samples, sampleRate: sampleRate, progress: progress)
    }

    /// How many chunks `separate` splits this many samples into, for sizing
    /// progress UI up front.
    public static func chunkCount(sampleCount: Int, sampleRate: UInt32) -> Int {
        Int(numChunks(nSamples: UInt64(max(sampleCount, 0)), sampleRate: sampleRate))
    }
}

// MARK: - Callback adapters

/// Shared by both listeners: the progress callback returns `false` once the
/// Swift task is cancelled, which is how Rust learns to stop.
private final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool { lock.withLock { cancelled } }

    func cancel() { lock.withLock { cancelled = true } }
}

private final class DownloadListener: FfiDownloadListener, @unchecked Sendable {
    private let handler: (@Sendable (DownloadProgress) -> Void)?
    private let flag = CancellationFlag()

    init(handler: (@Sendable (DownloadProgress) -> Void)?) {
        self.handler = handler
    }

    func cancel() { flag.cancel() }

    func onProgress(progress: FfiDownloadProgress) -> Bool {
        guard !flag.isCancelled else { return false }
        handler?(DownloadProgress(
            downloadedBytes: progress.downloadedBytes,
            totalBytes: progress.totalBytes,
            fraction: progress.fraction
        ))
        return true
    }
}

private final class SeparationListener: FfiSeparationListener, @unchecked Sendable {
    private let handler: (@Sendable (SeparationProgress) -> Void)?
    private let flag = CancellationFlag()

    init(handler: (@Sendable (SeparationProgress) -> Void)?) {
        self.handler = handler
    }

    func cancel() { flag.cancel() }

    func onProgress(progress: FfiSeparationProgress) -> Bool {
        guard !flag.isCancelled else { return false }
        handler?(SeparationProgress(
            fraction: progress.fraction,
            chunkIndex: progress.chunkIndex,
            totalChunks: progress.totalChunks
        ))
        return true
    }
}

// MARK: - Conversions

private func translatingErrors<T>(_ body: () async throws -> T) async throws -> T {
    do {
        return try await body()
    } catch let error as FfiDemucsError {
        throw DemucsError(error)
    }
}

extension DemucsError {
    init(_ error: FfiDemucsError) {
        switch error {
        case .Cancelled: self = .cancelled
        case .NotLoaded: self = .notLoaded
        case .NotCached(let modelId): self = .notDownloaded(modelID: modelId)
        case .InvalidInput(let reason): self = .invalidInput(reason)
        case .Download(let reason): self = .downloadFailed(reason)
        case .Io(let reason): self = .io(reason)
        case .Inference(let reason): self = .inferenceFailed(reason)
        }
    }
}

extension StemKind {
    var ffi: FfiStemKind {
        switch self {
        case .drums: .drums
        case .bass: .bass
        case .other: .other
        case .vocals: .vocals
        case .guitar: .guitar
        case .piano: .piano
        }
    }
}

extension FfiStemKind {
    var swift: StemKind {
        switch self {
        case .drums: .drums
        case .bass: .bass
        case .other: .other
        case .vocals: .vocals
        case .guitar: .guitar
        case .piano: .piano
        }
    }
}

extension DemucsModel {
    var ffi: FfiDemucsModel {
        switch self {
        case .fourStem: .fourStem
        case .sixStem: .sixStem
        case .fineTuned(let stems): .fineTuned(stems: stems.map(\.ffi))
        }
    }
}

extension FfiDemucsModel {
    var swift: DemucsModel {
        switch self {
        case .fourStem: .fourStem
        case .sixStem: .sixStem
        case .fineTuned(let stems): .fineTuned(stems: stems.map(\.swift))
        }
    }
}

private extension FfiModelMetadata {
    var swift: DemucsModelInfo {
        DemucsModelInfo(
            model: model.swift,
            id: id,
            label: label,
            description: description,
            sizeMB: sizeMb,
            stems: stems.map(\.swift)
        )
    }
}

private extension FfiStem {
    var swift: Stem {
        Stem(kind: kind.swift, left: left, right: right)
    }
}
