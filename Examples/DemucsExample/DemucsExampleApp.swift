import SwiftUI
import Demucs

@main
struct DemucsExampleApp: App {
    init() {
        // Keep the weights inside the app container.
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        DemucsEngine.configureCacheDirectory(caches.appendingPathComponent("demucs", isDirectory: true))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
