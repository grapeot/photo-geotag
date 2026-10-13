import Foundation

/// Where a stored session's track came from.
enum SessionSource: String, Codable {
    /// Recorded by the PhotoGeotag watch app and transferred over WatchConnectivity.
    case watch
    /// Imported from a workout route already recorded in Apple Health.
    case health
}

/// Sidecar metadata persisted next to each session's `.gpx` file.
private struct SessionMetadata: Codable {
    var isFinal: Bool
    var source: SessionSource
    /// Present only while the watch reports the outing as interrupted by
    /// another workout. Optional so older sidecars still decode.
    var isInterrupted: Bool?
}

/// A track session persisted in the app's Documents directory.
struct StoredSession: Identifiable, Hashable {
    let id: String
    let fileURL: URL
    let startDate: Date?
    let duration: TimeInterval
    let pointCount: Int
    /// `false` while the watch is still recording and only snapshots have
    /// arrived; `true` once the finalized track is received.
    let isFinal: Bool
    /// `true` when the watch lost its session to another workout and the outing
    /// is open, waiting to be resumed or discarded.
    let isInterrupted: Bool
    let source: SessionSource
}

/// Loads and stores received GPX sessions on disk.
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [StoredSession] = []
    /// Parsed tracks keyed by session id, cached during `reload()` so the list
    /// and detail views do not re-parse GPX on every render.
    private(set) var tracks: [String: GPXTrack] = [:]

    private let directory: URL
    private let exportsDirectory: URL

    init() {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("Sessions", isDirectory: true)
        exportsDirectory = base.appendingPathComponent("Exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        reload()
    }

    func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                includingPropertiesForKeys: nil)) ?? []
        var cache: [String: GPXTrack] = [:]
        var loaded: [StoredSession] = []
        for url in urls where url.pathExtension.lowercased() == "gpx" {
            guard let track = GPXParser.parse(contentsOf: url) else { continue }
            let id = url.deletingPathExtension().lastPathComponent
            let metadata = loadMetadata(id: id)
            cache[id] = track
            loaded.append(StoredSession(id: id,
                                        fileURL: url,
                                        startDate: track.startDate,
                                        duration: track.duration,
                                        pointCount: track.points.count,
                                        isFinal: metadata.isFinal,
                                        isInterrupted: metadata.isInterrupted ?? false,
                                        source: metadata.source))
        }
        tracks = cache
        sessions = loaded.sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
    }

    /// Imports (or refreshes) a session received from the watch. Snapshots and
    /// the final track share a session id, so a later transfer overwrites an
    /// earlier one.
    func importFile(from temporaryURL: URL,
                    sessionID: String,
                    isFinal: Bool,
                    isInterrupted: Bool = false,
                    source: SessionSource = .watch) {
        let destination = directory.appendingPathComponent("\(sessionID).gpx")
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
        } catch {
            return
        }
        saveMetadata(SessionMetadata(isFinal: isFinal,
                                     source: source,
                                     isInterrupted: isInterrupted ? true : nil),
                     id: sessionID)
        reload()
    }

    func delete(_ session: StoredSession) {
        try? FileManager.default.removeItem(at: session.fileURL)
        try? FileManager.default.removeItem(at: metadataURL(id: session.id))
        reload()
    }

    /// Writes GPS routes imported from Apple Health as finalized sessions. Ids are
    /// derived from the workout UUID, so re-importing updates in place.
    func importHealthRoutes(_ routes: [ImportedRoute]) {
        guard !routes.isEmpty else { return }
        for route in routes {
            let destination = directory.appendingPathComponent("\(route.id).gpx")
            let document = GPXWriter.document(name: route.track.name, points: route.track.points)
            guard (try? Data(document.utf8).write(to: destination)) != nil else { continue }
            saveMetadata(SessionMetadata(isFinal: true, source: .health, isInterrupted: nil), id: route.id)
        }
        reload()
    }

    func track(for session: StoredSession) -> GPXTrack? {
        tracks[session.id]
    }

    /// Builds a GPX file for the given sessions (one or many), splitting the
    /// output into `<trkseg>` runs wherever consecutive points are farther apart
    /// than the merge tolerance, and returns its temporary URL. Always applied,
    /// so a single session and a union are rendered the same way.
    func exportGPX(for sessions: [StoredSession]) -> URL? {
        let selectedTracks = sessions.compactMap { tracks[$0.id] }
        let points = TrackUnion.merge(selectedTracks)
        guard !points.isEmpty else { return nil }
        let document = GPXWriter.document(name: "Photo Track",
                                          points: points,
                                          segmentGap: TrackUnion.defaultSegmentGap)
        // Write into a stable, non-ephemeral folder (not tmp) so the share sheet
        // resolves it cleanly; drop earlier exports so they do not accumulate.
        try? FileManager.default.createDirectory(at: exportsDirectory, withIntermediateDirectories: true)
        if let existing = try? FileManager.default.contentsOfDirectory(at: exportsDirectory,
                                                                       includingPropertiesForKeys: nil) {
            for file in existing where file.pathExtension.lowercased() == "gpx" {
                try? FileManager.default.removeItem(at: file)
            }
        }
        let url = exportsDirectory.appendingPathComponent("merged-\(UUID().uuidString).gpx")
        guard (try? Data(document.utf8).write(to: url)) != nil else { return nil }
        return url
    }

    // MARK: - Metadata sidecars

    private func metadataURL(id: String) -> URL {
        directory.appendingPathComponent("\(id).meta.json")
    }

    private func loadMetadata(id: String) -> SessionMetadata {
        guard let data = try? Data(contentsOf: metadataURL(id: id)),
              let metadata = try? JSONDecoder().decode(SessionMetadata.self, from: data) else {
            // Legacy sessions written before metadata existed are final watch recordings.
            return SessionMetadata(isFinal: true, source: .watch)
        }
        return metadata
    }

    private func saveMetadata(_ metadata: SessionMetadata, id: String) {
        guard let data = try? JSONEncoder().encode(metadata) else { return }
        try? data.write(to: metadataURL(id: id))
    }
}
