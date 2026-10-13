import Foundation
import CoreLocation
import HealthKit

/// Records a GPS track for the lifetime of a single session.
///
/// The recorder starts an `HKWorkoutSession` purely to obtain sustained
/// background runtime and CoreLocation sensor access. It never finalizes the
/// associated workout builder, so no `HKWorkout` is ever written to Apple
/// Health or Fitness. Trackpoints are appended to an on-disk partial GPX file
/// as they arrive so that an unexpected termination loses at most the last few
/// seconds of data.
///
/// watchOS runs only one workout session at a time. If another workout (the
/// system Workout app or a third-party fitness app) starts while this app is
/// recording, WatchKit ends this app's session with
/// `HKError.Code.errorAnotherWorkoutSessionStarted`. The recorder treats that
/// as an abnormal termination: it finalizes and transfers whatever was
/// recorded and returns to idle instead of silently keeping a stale
/// "recording" state.
final class WatchRecorder: NSObject, ObservableObject {

    enum State: Equatable {
        case idle
        case recording
    }

    enum StopReason {
        case user
        case superseded
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var pointCount: Int = 0
    @Published private(set) var statusMessage: String?
    @Published var lastError: String?

    private let healthStore = HKHealthStore()
    private let locationManager = CLLocationManager()

    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?

    private var partialFileURL: URL?
    private var fileHandle: FileHandle?
    private var sessionStartDate: Date?
    private var activeSessionID: String?

    private let partialFileName = "current_session.gpx.part"
    private let sessionsDirectoryName = "Sessions"

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.activityType = .otherNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
    }

    // MARK: - Control

    func start() {
        guard state == .idle else { return }
        lastError = nil
        // A leftover partial file means a previous session never finalized.
        // Recover it before opening a fresh one so its points are not lost.
        recoverOrphanedRecordingIfNeeded()
        requestHealthAuthorization { [weak self] in
            self?.beginSession()
        }
    }

    func stop() {
        guard state == .recording else { return }
        finishRecording(reason: .user)
    }

    /// Recovers a track left on disk by a session that was terminated before it
    /// could stop cleanly (preemption, crash, or power loss). Safe to call on
    /// launch; it is a no-op when there is nothing to recover.
    func recoverOrphanedRecordingIfNeeded() {
        guard state == .idle else { return }
        let url = partialFileDiskURL()
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return }

        guard let track = GPXRecovery.rescuedTrack(fromPartial: data) else {
            try? FileManager.default.removeItem(at: url)
            return
        }

        let sessionID = UUID().uuidString
        let gpx = GPXWriter.document(name: "Photo Track", points: track.points)
        guard let destination = persist(gpxData: Data(gpx.utf8), sessionID: sessionID) else {
            return
        }
        try? FileManager.default.removeItem(at: url)
        WatchSessionTransmitter.shared.transfer(fileURL: destination,
                                                sessionID: sessionID,
                                                startDate: track.startDate,
                                                duration: track.duration)
        showStatus("Recovered unsent track")
    }

    // MARK: - Session lifecycle

    private func requestHealthAuthorization(completion: @escaping () -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion()
            return
        }
        let workoutType = HKObjectType.workoutType()
        healthStore.requestAuthorization(toShare: [workoutType], read: []) { _, _ in
            DispatchQueue.main.async(execute: completion)
        }
    }

    private func beginSession() {
        sessionStartDate = Date()
        activeSessionID = UUID().uuidString
        pointCount = 0
        openPartialFile()
        startLocationUpdates()
        startWorkoutSession()
        state = .recording
    }

    private func finishRecording(reason: StopReason) {
        guard state == .recording else { return }
        state = .idle
        locationManager.stopUpdatingLocation()

        let end = Date()
        switch reason {
        case .user:
            workoutSession?.end()
            // End data collection but never call `finishWorkout`, so the builder
            // is discarded and no workout, calories, or heart rate reaches Health.
            workoutBuilder?.endCollection(withEnd: end) { _, _ in }
        case .superseded:
            // The system already ended the session when the other workout
            // started; calling `end()` again is unnecessary.
            break
        }
        workoutSession = nil
        workoutBuilder = nil

        let status: String = reason == .user ? "Saved to iPhone"
                                               : "Stopped: another workout started"
        finalizeAndTransfer(endingAt: end, status: status)
    }

    private func openPartialFile() {
        let url = partialFileDiskURL()
        try? FileManager.default.removeItem(at: url)
        FileManager.default.createFile(atPath: url.path, contents: nil)

        guard let handle = try? FileHandle(forWritingTo: url) else {
            lastError = "Could not create the recording file."
            return
        }
        let header = GPXWriter.documentStart(name: "Photo Track", time: sessionStartDate)
        try? handle.write(contentsOf: Data(header.utf8))
        partialFileURL = url
        fileHandle = handle
    }

    private func startLocationUpdates() {
        // Do not set `allowsBackgroundLocationUpdates` on watchOS. Background
        // runtime is provided by the active `HKWorkoutSession`; setting the flag
        // trips a CoreLocation assertion (`CLClientIsBackgroundable`) because
        // watchOS has no iOS-style location background mode.
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
        locationManager.startUpdatingLocation()
    }

    private func startWorkoutSession() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .other
        configuration.locationType = .outdoor
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            session.delegate = self
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore,
                                                         workoutConfiguration: configuration)
            workoutSession = session
            workoutBuilder = builder
            let start = Date()
            session.startActivity(with: start)
            builder.beginCollection(withStart: start) { _, _ in }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func append(_ point: TrackPoint) {
        guard let fileHandle else { return }
        try? fileHandle.write(contentsOf: Data(GPXWriter.trackPoint(point).utf8))
        try? fileHandle.synchronize()
        DispatchQueue.main.async { [weak self] in
            self?.pointCount += 1
        }
    }

    private func finalizeAndTransfer(endingAt end: Date, status: String) {
        guard let url = partialFileURL, let handle = fileHandle else { return }
        try? handle.write(contentsOf: Data(GPXWriter.documentEnd.utf8))
        try? handle.close()
        fileHandle = nil
        partialFileURL = nil

        let sessionID = activeSessionID ?? UUID().uuidString
        guard let destination = persist(movingFrom: url, sessionID: sessionID) else { return }

        let duration = sessionStartDate.map { end.timeIntervalSince($0) } ?? 0
        WatchSessionTransmitter.shared.transfer(fileURL: destination,
                                                sessionID: sessionID,
                                                startDate: sessionStartDate,
                                                duration: duration)

        sessionStartDate = nil
        activeSessionID = nil
        pointCount = 0
        showStatus(status)
    }

    // MARK: - Storage helpers

    private func partialFileDiskURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(partialFileName)
    }

    private func sessionsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(sessionsDirectoryName, isDirectory: true)
    }

    /// Moves a finalized partial file into the sessions directory.
    private func persist(movingFrom url: URL, sessionID: String) -> URL? {
        let directory = sessionsDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("\(sessionID).gpx")
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    /// Writes recovered GPX bytes into the sessions directory.
    private func persist(gpxData: Data, sessionID: String) -> URL? {
        let directory = sessionsDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("\(sessionID).gpx")
        do {
            try gpxData.write(to: destination)
            return destination
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    private func showStatus(_ message: String) {
        statusMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.statusMessage = nil
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension WatchRecorder: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard state == .recording else { return }
        for location in locations where location.horizontalAccuracy >= 0 {
            append(TrackPoint(latitude: location.coordinate.latitude,
                              longitude: location.coordinate.longitude,
                              elevation: location.altitude,
                              time: location.timestamp))
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Transient location errors are expected outdoors; keep the session alive.
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WatchRecorder: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState,
                        date: Date) {
        guard toState == .ended else { return }
        DispatchQueue.main.async { [weak self] in
            self?.handleSessionEndedExternally()
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        let superseded = (error as? HKError)?.code == .errorAnotherWorkoutSessionStarted
        DispatchQueue.main.async { [weak self] in
            self?.lastError = error.localizedDescription
            if superseded {
                self?.handleSessionEndedExternally()
            }
        }
    }

    /// Called when watchOS ends the workout session for us. When a user-initiated
    /// stop already moved the recorder to `.idle`, this is a no-op.
    private func handleSessionEndedExternally() {
        guard state == .recording else { return }
        finishRecording(reason: .superseded)
    }
}
