import Testing
@testable import Demucs

@Test func modelsRoundTripThroughTheBridge() {
    let models: [DemucsModel] = [.fourStem, .sixStem, .fineTunedAll, .fineTuned(stems: [.vocals])]
    for model in models {
        #expect(model.ffi.swift == model)
    }
}

@Test func stemKindsRoundTripThroughTheBridge() {
    for kind in StemKind.allCases {
        #expect(kind.ffi.swift == kind)
    }
}

@Test func bridgeErrorsMapToPublicErrors() {
    #expect(DemucsError(.Cancelled) == .cancelled)
    #expect(DemucsError(.NotLoaded) == .notLoaded)
    #expect(DemucsError(.NotCached(modelId: "htdemucs")) == .notDownloaded(modelID: "htdemucs"))
    #expect(DemucsError(.InvalidInput(reason: "empty")) == .invalidInput("empty"))
}

@Test func modelCatalogMatchesTheRustSide() {
    let models = DemucsEngine.models
    #expect(models.map(\.id) == ["htdemucs", "htdemucs_6s", "htdemucs_ft"])
    #expect(DemucsEngine.info(for: .sixStem).stems.contains(.guitar))
    #expect(DemucsEngine.info(for: .fineTunedAll).sizeMB > DemucsEngine.info(for: .fourStem).sizeMB)
}

@Test func chunkCountAccountsForSampleRate() {
    let oneChunk = 343_980
    #expect(DemucsEngine.chunkCount(sampleCount: oneChunk, sampleRate: 44_100) == 1)
    #expect(DemucsEngine.chunkCount(sampleCount: oneChunk, sampleRate: 22_050) > 1)
}

@Test func separatingWithoutAModelFails() async {
    let engine = DemucsEngine()
    #expect(!engine.isLoaded)
    await #expect(throws: DemucsError.notLoaded) {
        try await engine.separate(mono: [0, 0, 0, 0], sampleRate: 44_100)
    }
}

@Test func mismatchedChannelsAreRejected() async {
    let engine = DemucsEngine()
    await #expect(throws: DemucsError.self) {
        try await engine.separate(left: [0, 0], right: [0], sampleRate: 44_100)
    }
}
