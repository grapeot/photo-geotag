import Foundation

/// A track session persisted in the app's Documents directory.
struct StoredSession: Identifiable, Hashable {
    let id: String
    let fileURL: URL
    let startDate: Date?
    let duration: TimeInterval
    let pointCount: Int
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
                return StoredSession(id: url.deletingPathExtension().lastPathComponent,
                                     fileURL: url,
                                     startDate: track.startDate,
                                     duration: track.duration,
                                     pointCount: track.points.count)
            }
            .sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
    }

    func importFile(from temporaryURL: URL, sessionID: String) {
        let destination = directory.appendingPathComponent("\(sessionID).gpx")
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
        } catch {
            return
        }
        reload()
    }

    func delete(_ session: StoredSession) {
        try? FileManager.default.removeItem(at: session.fileURL)
        reload()
    }

    func track(for session: StoredSession) -> GPXTrack? {
        GPXParser.parse(contentsOf: session.fileURL)
    }
}
