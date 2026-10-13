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
    let source: SessionSource
}

/// Loads and stores received GPX sessions on disk.
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [StoredSession] = []

    private let directory: URL

    init() {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("Sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        reload()
    }

    func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                includingPropertiesForKeys: nil)) ?? []
        sessions = urls
            .filter { $0.pathExtension.lowercased() == "gpx" }
            .compactMap { url -> StoredSession? in
                guard let track = GPXParser.parse(contentsOf: url) else { return nil }
                let id = url.deletingPathExtension().lastPathComponent
                let metadata = loadMetadata(id: id)
                return StoredSession(id: id,
                                     fileURL: url,
                                     startDate: track.startDate,
                                     duration: track.duration,
                                     pointCount: track.points.count,
                                     isFinal: metadata.isFinal,
                                     source: metadata.source)
            }
            .sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
    }

    /// Imports (or refreshes) a session received from the watch. Snapshots and
    /// the final track share a session id, so a later transfer overwrites an
    /// earlier one.
    func importFile(from temporaryURL: URL, sessionID: String, isFinal: Bool, source: SessionSource = .watch) {
        let destination = directory.appendingPathComponent("\(sessionID).gpx")
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
        } catch {
            return
        }
        saveMetadata(SessionMetadata(isFinal: isFinal, source: source), id: sessionID)
        reload()
    }

    func delete(_ session: StoredSession) {
        try? FileManager.default.removeItem(at: session.fileURL)
        try? FileManager.default.removeItem(at: metadataURL(id: session.id))
        reload()
    }

    func track(for session: StoredSession) -> GPXTrack? {
        GPXParser.parse(contentsOf: session.fileURL)
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
