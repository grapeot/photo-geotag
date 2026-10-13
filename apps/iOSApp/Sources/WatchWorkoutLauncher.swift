import Foundation
import HealthKit

/// Asks the paired Apple Watch to resume recording, from the iPhone.
///
/// This uses `HKHealthStore.startWatchApp(with:)`, which launches or wakes the
/// companion watchOS app and delivers a workout configuration to its delegate,
/// so the user can resume an interrupted outing without touching the watch. The
/// watch app decides whether to resume its open outing or start a new one.
final class WatchWorkoutLauncher {

    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func resumeOnWatch(completion: @escaping (Bool) -> Void) {
        guard isAvailable else {
            DispatchQueue.main.async { completion(false) }
            return
        }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .other
        configuration.locationType = .outdoor
        store.startWatchApp(with: configuration) { success, _ in
            DispatchQueue.main.async { completion(success) }
        }
    }
}
