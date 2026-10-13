import Foundation
import CoreLocation
import HealthKit

/// A GPS track read back from a workout route already recorded in Apple Health.
struct ImportedRoute {
    let id: String
    let track: GPXTrack
}

/// Reads workout routes out of Apple Health so a track the user already recorded
/// with the system Workout app (or another fitness app) can be reused for
/// geotagging.
///
/// This reads **route geometry only**. It never requests or surfaces heart rate,
/// active energy, or any other health metric, and it never writes to Health.
final class HealthRouteImporter {

    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Requests read access to workouts and their routes.
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        guard isAvailable else {
            DispatchQueue.main.async { completion(false) }
            return
        }
        let typesToRead: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute()
        ]
        store.requestAuthorization(toShare: [], read: typesToRead) { success, _ in
            DispatchQueue.main.async { completion(success) }
        }
    }

    /// Imports every workout route that starts on or after `startDate`, newest
    /// first. Routes with fewer than two usable fixes are skipped.
    func importRoutes(since startDate: Date, completion: @escaping ([ImportedRoute]) -> Void) {
        guard isAvailable else {
            DispatchQueue.main.async { completion([]) }
            return
        }
        let predicate = HKQuery.predicateForSamples(withStart: startDate,
                                                    end: Date(),
                                                    options: .strictStartDate)
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
        let query = HKSampleQuery(sampleType: .workoutType(),
                                  predicate: predicate,
                                  limit: HKObjectQueryNoLimit,
                                  sortDescriptors: sort) { [weak self] _, samples, _ in
            guard let self, let workouts = samples as? [HKWorkout] else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            self.loadRoutes(for: workouts, completion: completion)
        }
        store.execute(query)
    }

    // MARK: - Private

    private func loadRoutes(for workouts: [HKWorkout], completion: @escaping ([ImportedRoute]) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        var results: [ImportedRoute] = []

        for workout in workouts {
            group.enter()
            routes(for: workout) { [weak self] routes in
                guard let self else {
                    group.leave()
                    return
                }
                let routeGroup = DispatchGroup()
                let pointLock = NSLock()
                var points: [TrackPoint] = []
                for route in routes {
                    routeGroup.enter()
                    self.locations(for: route) { locations in
                        pointLock.lock()
                        points.append(contentsOf: locations)
                        pointLock.unlock()
                        routeGroup.leave()
                    }
                }
                routeGroup.notify(queue: .global()) {
                    let sorted = points.sorted { $0.time < $1.time }
                    if sorted.count > 1 {
                        let track = GPXTrack(name: "Health Workout", points: sorted)
                        lock.lock()
                        results.append(ImportedRoute(id: "health-\(workout.uuid.uuidString)", track: track))
                        lock.unlock()
                    }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            completion(results.sorted { ($0.track.startDate ?? .distantPast) > ($1.track.startDate ?? .distantPast) })
        }
    }

    private func routes(for workout: HKWorkout, completion: @escaping ([HKWorkoutRoute]) -> Void) {
        let predicate = HKQuery.predicateForObjects(from: workout)
        let query = HKAnchoredObjectQuery(type: HKSeriesType.workoutRoute(),
                                          predicate: predicate,
                                          anchor: nil,
                                          limit: HKObjectQueryNoLimit) { _, samples, _, _, _ in
            completion((samples as? [HKWorkoutRoute]) ?? [])
        }
        store.execute(query)
    }

    private func locations(for route: HKWorkoutRoute, completion: @escaping ([TrackPoint]) -> Void) {
        var points: [TrackPoint] = []
        let query = HKWorkoutRouteQuery(route: route) { _, locations, done, _ in
            if let locations {
                points.append(contentsOf: locations.compactMap { location in
                    guard location.horizontalAccuracy >= 0 else { return nil }
                    return TrackPoint(latitude: location.coordinate.latitude,
                                      longitude: location.coordinate.longitude,
                                      elevation: location.altitude,
                                      time: location.timestamp)
                })
            }
            if done {
                completion(points)
            }
        }
        store.execute(query)
    }
}
