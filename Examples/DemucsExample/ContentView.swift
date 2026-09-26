import Demucs
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = SeparationViewModel()
    @State private var importing = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Model") {
                    Picker("Model", selection: $viewModel.model) {
                        ForEach(DemucsEngine.models) { info in
                            Text("\(info.label) · \(info.sizeMB) MB").tag(info.model)
                        }
                    }
                    .disabled(viewModel.isBusy)
                }

                Section {
                    Button("Choose Audio File…") { importing = true }
                        .disabled(viewModel.isBusy)
                    status
                    if viewModel.isBusy {
                        Button("Cancel", role: .destructive) { viewModel.cancel() }
                    }
                }

                if !viewModel.stems.isEmpty {
                    Section("Stems") {
                        ForEach(viewModel.stems) { stem in
                            ShareLink(item: stem.url) {
                                Label(stem.kind.rawValue.capitalized, systemImage: "waveform")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Demucs")
            .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { result in
                if case .success(let url) = result {
                    viewModel.separate(fileAt: url)
                }
            }
        }
    }

    @ViewBuilder private var status: some View {
        switch viewModel.phase {
        case .idle:
            EmptyView()
        case .downloading(let fraction):
            ProgressView("Downloading model", value: fraction)
        case .loading:
            ProgressView("Loading model")
        case .separating(let fraction):
            ProgressView("Separating", value: fraction)
        case .done:
            Label("Done", systemImage: "checkmark.circle")
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
    }
}
