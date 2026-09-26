import AVFoundation
import Demucs
import Foundation

struct StemFile: Identifiable {
    let kind: StemKind
    let url: URL
    var id: StemKind { kind }
}

@MainActor
final class SeparationViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case downloading(Double)
        case loading
        case separating(Double)
        case done
        case failed(String)
    }

    @Published var model: DemucsModel = .fourStem
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var stems: [StemFile] = []

    private let engine = DemucsEngine()
    private var task: Task<Void, Never>?
    /// Bumped on every new run so a cancelled run that unwinds late can't
    /// overwrite the state of the run that replaced it.
    private var generation = 0

    var isBusy: Bool {
        switch phase {
        case .downloading, .loading, .separating: true
        default: false
        }
    }

    func separate(fileAt url: URL) {
        task?.cancel()
        stems = []
        generation += 1
        let current = generation
        task = Task { await run(url: url, generation: current) }
    }

    func cancel() {
        task?.cancel()
    }

    /// Progress arrives from background threads and can land after the step
    /// it describes has finished; only apply it while that step is current.
    private func update(_ progress: Phase) {
        switch (phase, progress) {
        case (.downloading, .downloading), (.separating, .separating):
            phase = progress
        default:
            break
        }
    }

    private func run(url: URL, generation current: Int) async {
        do {
            let model = model
            if !DemucsEngine.isDownloaded(model) {
                phase = .downloading(0)
                try await DemucsEngine.download(model) { progress in
                    Task { @MainActor in self.update(.downloading(progress.fraction)) }
                }
            }
            if engine.loadedModel != model {
                phase = .loading
                try await engine.load(model)
            }

            let audio = try AudioFile.read(url)
            phase = .separating(0)
            let separated = try await engine.separate(
                left: audio.left,
                right: audio.right,
                sampleRate: audio.sampleRate
            ) { progress in
                Task { @MainActor in self.update(.separating(progress.fraction)) }
            }

            let outputDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent(url.deletingPathExtension().lastPathComponent, isDirectory: true)
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            guard current == generation else { return }
            stems = try separated.map { stem in
                let file = outputDirectory.appendingPathComponent("\(stem.kind.rawValue).wav")
                try AudioFile.write(stem, sampleRate: audio.sampleRate, to: file)
                return StemFile(kind: stem.kind, url: file)
            }
            guard current == generation else { return }
            phase = .done
        } catch {
            guard current == generation else { return }
            switch error {
            case DemucsError.cancelled, is CancellationError:
                phase = .idle
            default:
                phase = .failed(error.localizedDescription)
            }
        }
    }
}

/// Minimal AVFoundation decode/encode. Demucs itself takes and returns plain
/// per-channel Float arrays at any sample rate.
enum AudioFile {
    struct Decoded {
        let left: [Float]
        let right: [Float]
        let sampleRate: UInt32
    }

    static func read(_ url: URL) throws -> Decoded {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        // Force Float32 so 16/24-bit PCM files decode into floatChannelData.
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw DemucsError.invalidInput("Could not allocate an audio buffer.")
        }
        try file.read(into: buffer)
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else {
            throw DemucsError.invalidInput("The file has no audio.")
        }
        let frames = Int(buffer.frameLength)
        let left = Array(UnsafeBufferPointer(start: channels[0], count: frames))
        let right = format.channelCount > 1
            ? Array(UnsafeBufferPointer(start: channels[1], count: frames))
            : left
        return Decoded(left: left, right: right, sampleRate: UInt32(format.sampleRate))
    }

    static func write(_ stem: Stem, sampleRate: UInt32, to url: URL) throws {
        guard
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: Double(sampleRate),
                channels: 2,
                interleaved: false
            ),
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(stem.left.count)),
            let channels = buffer.floatChannelData
        else {
            throw DemucsError.io("Could not allocate an audio buffer.")
        }
        buffer.frameLength = AVAudioFrameCount(stem.left.count)
        for (index, samples) in [stem.left, stem.right].enumerated() {
            samples.withUnsafeBufferPointer { source in
                guard let base = source.baseAddress else { return }
                channels[index].update(from: base, count: source.count)
            }
        }

        try? FileManager.default.removeItem(at: url)
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }
}
