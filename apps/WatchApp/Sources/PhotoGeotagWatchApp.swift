import SwiftUI

@main
struct PhotoGeotagWatchApp: App {
    @StateObject private var recorder = WatchRecorder()

    init() {
        WatchSessionTransmitter.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(recorder)
        }
    }
}
