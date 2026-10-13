import Foundation

/// A single GPS sample inside a recorded track.
struct TrackPoint: Codable, Hashable {
    var latitude: Double
    var longitude: Double
    var elevation: Double?
    var time: Date
}

/// A recorded GPS track ordered by time.
struct GPXTrack: Codable, Hashable {
    var name: String
    var points: [TrackPoint]

    var startDate: Date? { points.first?.time }
    var endDate: Date? { points.last?.time }

    var duration: TimeInterval {
        guard let start = startDate, let end = endDate else { return 0 }
        return max(0, end.timeIntervalSince(start))
    }
}

/// UTC ISO 8601 timestamps without fractional seconds, as required by GPX 1.1.
enum GPXTimestamp {
    static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    static func date(from string: String) -> Date? {
        formatter.date(from: string) ?? fractionalFormatter.date(from: string)
    }
}

/// Serializes trackpoints to GPX 1.1.
///
/// The document is split into a prologue, per-point elements, and an epilogue
/// so the watch app can append points incrementally to an on-disk partial file
/// and close the document only when recording stops.
enum GPXWriter {
    static func documentStart(name: String, time: Date?) -> String {
        var lines = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<gpx version=\"1.1\" creator=\"PhotoGeotag\" xmlns=\"http://www.topografix.com/GPX/1/1\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xsi:schemaLocation=\"http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd\">",
            "  <metadata>",
            "    <name>\(escape(name))</name>"
        ]
        if let time {
            lines.append("    <time>\(GPXTimestamp.string(from: time))</time>")
        }
        lines.append(contentsOf: [
            "  </metadata>",
            "  <trk>",
            "    <name>\(escape(name))</name>",
            "    <trkseg>"
        ])
        return lines.joined(separator: "\n") + "\n"
    }

    static let documentEnd = "    </trkseg>\n  </trk>\n</gpx>\n"

    static func trackPoint(_ point: TrackPoint) -> String {
        var lines = [
            "      <trkpt lat=\"\(decimal(point.latitude))\" lon=\"\(decimal(point.longitude))\">"
        ]
        if let elevation = point.elevation {
            lines.append("        <ele>\(decimal(elevation))</ele>")
        }
        lines.append("        <time>\(GPXTimestamp.string(from: point.time))</time>")
        lines.append("      </trkpt>")
        return lines.joined(separator: "\n") + "\n"
    }

    static func document(name: String, points: [TrackPoint]) -> String {
        var document = documentStart(name: name, time: points.first?.time)
        for point in points {
            document += trackPoint(point)
        }
        document += documentEnd
        return document
    }

    /// Formats coordinates with a fixed C locale so GPX always uses `.` as the
    /// decimal separator regardless of the device locale.
    private static func decimal(_ value: Double) -> String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

/// Recovers a track from a partially written on-disk GPX file.
///
/// The recorder streams points into `current_session.gpx.part` and only closes
/// the document on Stop. If the app is terminated mid-session (battery, crash,
/// or a system preemption), the file is left without its closing tags. This
/// helper closes the document and returns the points that were safely flushed,
/// or `nil` when the fragment holds no usable track.
enum GPXRecovery {
    static func rescuedTrack(fromPartial data: Data) -> GPXTrack? {
        guard var text = String(data: data, encoding: .utf8) else { return nil }
        if !text.contains("</gpx>") {
            if text.contains("<trkseg>") {
                text += GPXWriter.documentEnd
            } else {
                text += "</gpx>\n"
            }
        }
        guard let track = GPXParser.parse(data: Data(text.utf8)),
              !track.points.isEmpty else { return nil }
        return track
    }
}
