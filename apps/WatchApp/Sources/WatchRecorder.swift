import Foundation
import CoreLocation
import HealthKit
import WatchKit

/// Records a GPS track for the lifetime of a single outing.
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
/// `HKError.Code.errorAnotherWorkoutSessionStarted`. Rather than closing the
/// outing, the recorder keeps the partial file and moves to `interrupted`, so a
/// resume continues the same outing (one track per outing) and a later stop or
/// discard finalizes it.
final class WatchRecorder: NSObject, ObservableObject {

    static let shared = WatchRecorder()

    enum State: Equatable {
        case idle
        case recording
        /// The workout session was taken away by another workout; the outing is
        /// open and can be resumed or discarded.
        case interrupted
    }

    enum StopReason {
        case user
        /// Another workout took the session; keep the outing open.
        case superseded
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var isPreparing = false
    @Published private(set) var pointCount: Int = 0
    @Published private(set) var statusMessage: String?
    @Published var alertMessage: String?
    @Published var lastError: String?

    private let healthStore = HKHealthStore()
    private let locationManager = CLLocationManager()

    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?

    private var partialFileURL: URL?
    private var fileHandle: FileHandle?
    private var sessionStartDate: Date?
    private var activeSessionID: String?

    /// A start or resume is waiting for the session to reach `.running`; only
    /// then do we commit to recording. If it fails first, we refuse cleanly.
    private enum PendingStart {
        case new
        case resume(url: URL, id: String)
    }
    private var pendingStart: PendingStart?

    private var snapshotTimer: Timer?
    private var snapshotSequence = 0
    private let snapshotInterval: TimeInterval = 300

    private let activePartialName = "active.gpx.part"
    private let interruptedPrefix = "interrupted_"
    private let interruptedSuffix = ".gpx.part"
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
        guard state == .idle, !isPreparing else { return }
        lastError = nil
        alertMessage = nil
        recoverOrphanedRecordingIfNeeded()
        requestHealthAuthorization { [weak self] in
            self?.prepareStart(.new)
        }
    }

    func stop() {
        guard state == .recording else { return }
        finishRecording(reason: .user)
    }

    /// Resumes an interrupted outing, continuing the same session and file.
    func resume() {
        guard state == .interrupted, !isPreparing else { return }
        guard let (url, id) = firstInterruptedFile() else {
            state = .idle
            return
        }
        lastError = nil
        alertMessage = nil
        requestHealthAuthorization { [weak self] in
            self?.prepareStart(.resume(url: url, id: id))
        }
    }

    /// Closes an interrupted outing for good, transferring what was recorded.
    func discardInterrupted() {
        guard state == .interrupted else { return }
        guard let (url, id) = firstInterruptedFile() else {
            state = .idle
            return
        }
        finalizeFile(at: url, sessionID: id, status: "Saved to iPhone")
        state = .idle
    }

    /// Restores state on launch: an interrupted outing offers resume/discard; a
    /// plain partial file (crash mid-recording) is recovered and transferred.
    func recoverOnLaunch() {
        if let (url, id) = firstInterruptedFile() {
            activeSessionID = id
            pointCount = GPXParser.parse(contentsOf: url)?.points.count ?? 0
            state = .interrupted
            return
        }
        recoverOrphanedRecordingIfNeeded()
    }

    /// Called when the iPhone asks the watch to resume (via
    /// `HKHealthStore.startWatchApp`). Resumes an interrupted outing, or starts
    /// a fresh one if nothing is open.
    func resumeFromPhone() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch self.state {
            case .interrupted:
                self.resume()
            case .idle:
                self.start()
            case .recording:
                break
            }
        }
    }

    // MARK: - Session lifecycle

    private func prepareStart(_ pending: PendingStart) {
        isPreparing = true
        pendingStart = pending
        startLocationUpdates()
        startWorkoutSession()
    }

    private func confirmStart() {
        guard let pending = pendingStart else { return }
        pendingStart = nil
        isPreparing = false

        switch pending {
        case .new:
            activeSessionID = UUID().uuidString
            sessionStartDate = Date()
            pointCount = 0
            snapshotSequence = 0
            openNewPartialFile()
        case .resume(let url, let id):
            activeSessionID = id
            if let track = GPXParser.parse(contentsOf: url) {
                pointCount = track.points.count
                sessionStartDate = track.startDate
            }
            reopenPartialFile(url)
        }

        state = .recording
        startSnapshotTimer()
    }

    private func failStart() {
        guard pendingStart != nil else { return }
        pendingStart = nil
        isPreparing = false
        locationManager.stopUpdatingLocation()
        workoutSession = nil
        workoutBuilder = nil
        alertMessage = "Another workout is already running."
    }

    private func finishRecording(reason: StopReason) {
        guard state == .recording else { return }
        stopSnapshotTimer()
        locationManager.stopUpdatingLocation()

        let end = Date()
        if reason == .user {
            workoutSession?.end()
            // End data collection but never call `finishWorkout`, so the builder
            // is discarded and no workout, calories, or heart rate reaches Health.
            workoutBuilder?.endCollection(withEnd: end) { _, _ in }
        }
        workoutSession = nil
        workoutBuilder = nil

        switch reason {
        case .user:
            finalizeActiveRecording()
            state = .idle
        case .superseded:
            markInterrupted()
        }
    }

    // MARK: - File handling

    private func openNewPartialFile() {
        let url = activePartialFileURL()
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

    /// Reopens an interrupted partial file and starts a new `<trkseg>` so the
    /// resumed run is a separate segment, not a line across the gap.
    private func reopenPartialFile(_ url: URL) {
        guard let handle = try? FileHandle(forWritingTo: url) else {
            lastError = "Could not reopen the recording file."
            return
        }
        try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(GPXWriter.segmentBreak.utf8))
        partialFileURL = url
        fileHandle = handle
    }

    private func append(_ point: TrackPoint) {
        guard let fileHandle else { return }
        try? fileHandle.write(contentsOf: Data(GPXWriter.trackPoint(point).utf8))
        try? fileHandle.synchronize()
        DispatchQueue.main.async { [weak self] in
            self?.pointCount += 1
        }
    }

    private func finalizeActiveRecording() {
        guard let url = partialFileURL, let handle = fileHandle else { return }
        try? handle.write(contentsOf: Data(GPXWriter.documentEnd.utf8))
        try? handle.close()
        fileHandle = nil
        partialFileURL = nil

        let sessionID = activeSessionID ?? UUID().uuidString
        guard let destination = persist(movingFrom: url, sessionID: sessionID) else { return }
        let duration = sessionStartDate.map { Date().timeIntervalSince($0) } ?? 0
        WatchSessionTransmitter.shared.transfer(fileURL: destination,
                                                sessionID: sessionID,
                                                startDate: sessionStartDate,
                                                duration: duration,
                                                isFinal: true,
                                                state: WatchTransferState.recording)
        resetOuting()
        showStatus("Saved to iPhone")
    }

    /// Keeps the partial file, moves it under the interrupted name, and tells
    /// the phone the outing is interrupted. The session id is preserved so a
    /// resume continues the same outing.
    private func markInterrupted() {
        try? fileHandle?.close()
        fileHandle = nil
        let id = activeSessionID ?? UUID().uuidString
        activeSessionID = id

        var url = partialFileURL
        let interrupted = interruptedFileURL(id: id)
        if let current = partialFileURL, current != interrupted {
            try? FileManager.default.removeItem(at: interrupted)
            if (try? FileManager.default.moveItem(at: current, to: interrupted)) != nil {
                url = interrupted
            }
        }
        let fileURL = url ?? interrupted
        partialFileURL = nil

        state = .interrupted
        WKInterfaceDevice.current().play(.notification)

        let duration = sessionStartDate.map { Date().timeIntervalSince($0) } ?? 0
        WatchSessionTransmitter.shared.transfer(fileURL: fileURL,
                                                sessionID: id,
                                                startDate: sessionStartDate,
                                                duration: duration,
                                                isFinal: false,
                                                state: WatchTransferState.interrupted)
    }

    private func finalizeFile(at url: URL, sessionID: String, status: String) {
        guard var data = try? Data(contentsOf: url) else { return }
        if !data.containsASCII("</gpx>") {
            data.append(Data(GPXWriter.documentEnd.utf8))
        }
        guard let destination = persist(gpxData: data, sessionID: sessionID) else { return }
        try? FileManager.default.removeItem(at: url)
        let track = GPXParser.parse(data: data)
        let duration = track?.duration ?? 0
        WatchSessionTransmitter.shared.transfer(fileURL: destination,
                                                sessionID: sessionID,
                                                startDate: track?.startDate,
                                                duration: duration,
                                                isFinal: true,
                                                state: WatchTransferState.recording)
        resetOuting()
        showStatus(status)
    }

    /// Recovers a track left by a session terminated before it could stop
    /// cleanly (a crash, not a preemption).
    private func recoverOrphanedRecordingIfNeeded() {
        guard state == .idle else { return }
        let url = activePartialFileURL()
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return }

        guard let track = GPXRecovery.rescuedTrack(fromPartial: data) else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        let sessionID = UUID().uuidString
        let gpx = GPXWriter.document(name: "Photo Track", points: track.points)
        guard let destination = persist(gpxData: Data(gpx.utf8), sessionID: sessionID) else { return }
        try? FileManager.default.removeItem(at: url)
        WatchSessionTransmitter.shared.transfer(fileURL: destination,
                                                sessionID: sessionID,
                                                startDate: track.startDate,
                                                duration: track.duration,
                                                isFinal: true,
                                                state: WatchTransferState.recording)
        showStatus("Recovered unsent track")
    }

    // MARK: - Incremental snapshots

    private func startSnapshotTimer() {
        stopSnapshotTimer()
        let timer = Timer(timeInterval: snapshotInterval, repeats: true) { [weak self] _ in
            self?.sendSnapshot()
        }
        RunLoop.main.add(timer, forMode: .common)
        snapshotTimer = timer
    }

    private func stopSnapshotTimer() {
        snapshotTimer?.invalidate()
        snapshotTimer = nil
    }

    /// Sends a finalized copy of the in-progress track so the iPhone can show a
    /// growing route and keep partial data if the watch dies mid-session.
    private func sendSnapshot() {
        guard state == .recording, let url = partialFileURL else { return }
        guard let data = try? Data(contentsOf: url),
              let track = GPXRecovery.rescuedTrack(fromPartial: data),
              let sessionID = activeSessionID else { return }

        snapshotSequence += 1
        let document = GPXWriter.document(name: "Photo Track",
                                          points: track.points,
                                          segmentGap: TrackUnion.defaultSegmentGap)
        let snapshotURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("snapshot-\(sessionID)-\(snapshotSequence).gpx")
        guard (try? Data(document.utf8).write(to: snapshotURL)) != nil else { return }

        let duration = sessionStartDate.map { Date().timeIntervalSince($0) } ?? 0
        WatchSessionTransmitter.shared.transfer(fileURL: snapshotURL,
                                                sessionID: sessionID,
                                                startDate: sessionStartDate,
                                                duration: duration,
                                                sequence: snapshotSequence,
                                                isFinal: false,
                                                state: WatchTransferState.recording)
    }

    // MARK: - Workout session

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
            DispatchQueue.main.async { [weak self] in
                self?.failStart()
            }
        }
    }

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

    // MARK: - Storage helpers

    private func documentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func activePartialFileURL() -> URL {
        documentsDirectory().appendingPathComponent(activePartialName)
    }

    private func interruptedFileURL(id: String) -> URL {
        documentsDirectory().appendingPathComponent("\(interruptedPrefix)\(id)\(interruptedSuffix)")
    }

    private func firstInterruptedFile() -> (URL, String)? {
        let files = (try? FileManager.default.contentsOfDirectory(at: documentsDirectory(),
                                                                  includingPropertiesForKeys: nil)) ?? []
        guard let url = files.first(where: { $0.lastPathComponent.hasPrefix(interruptedPrefix)
            && $0.lastPathComponent.hasSuffix(interruptedSuffix) }) else { return nil }
        let name = url.lastPathComponent
        let start = name.index(name.startIndex, offsetBy: interruptedPrefix.count)
        let end = name.index(name.endIndex, offsetBy: -interruptedSuffix.count)
        return (url, String(name[start..<end]))
    }

    private func sessionsDirectory() -> URL {
        documentsDirectory().appendingPathComponent(sessionsDirectoryName, isDirectory: true)
    }

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

    private func resetOuting() {
        sessionStartDate = nil
        activeSessionID = nil
        pointCount = 0
        snapshotSequence = 0
    }

    private func showStatus(_ message: String) {
        statusMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.statusMessage = nil
        }
    }
}

private extension Data {
    func containsASCII(_ needle: String) -> Bool {
        guard let string = String(data: self, encoding: .utf8) else { return false }
        return string.contains(needle)
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
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch toState {
            case .running:
                self.confirmStart()
            case .ended:
                if self.pendingStart != nil {
                    self.failStart()
                } else if self.state == .recording {
                    self.finishRecording(reason: .superseded)
                }
            default:
                break
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        let superseded = (error as? HKError)?.code == .errorAnotherWorkoutSessionStarted
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lastError = error.localizedDescription
            guard superseded else { return }
            if self.pendingStart != nil {
                self.failStart()
            } else if self.state == .recording {
                self.finishRecording(reason: .superseded)
            }
        }
    }
}
