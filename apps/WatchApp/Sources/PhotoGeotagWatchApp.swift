import SwiftUI
import HealthKit

@main
struct PhotoGeotagWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate
    @StateObject private var recorder = WatchRecorder.shared

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

/// Receives workout requests from the paired iPhone. When the iPhone calls
/// `HKHealthStore.startWatchApp(with:)`, the system launches or wakes this app
/// and passes the configuration here.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        WatchRecorder.shared.resumeFromPhone()
    }
}
