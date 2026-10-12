import Foundation

/// Parses GPX 1.1 `<trkpt lat lon>` elements into a `GPXTrack`.
final class GPXParser: NSObject, XMLParserDelegate {
    private var points: [TrackPoint] = []
    private var trackName = ""
    private var currentLatitude: Double?
    private var currentLongitude: Double?
    private var currentElevation: Double?
    private var currentTime: Date?
    private var textBuffer = ""
    private var inTrackPoint = false
    private var readingElevation = false
    private var readingTime = false
    private var readingName = false

    static func parse(data: Data) -> GPXTrack? {
        let parser = GPXParser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        guard xml.parse() else { return nil }
        let name = parser.trackName.isEmpty ? "Photo Track" : parser.trackName
        return GPXTrack(name: name, points: parser.points)
    }

    static func parse(contentsOf url: URL) -> GPXTrack? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return parse(data: data)
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String]) {
        switch elementName {
        case "trkpt":
            inTrackPoint = true
            currentLatitude = attributeDict["lat"].flatMap(Double.init)
            currentLongitude = attributeDict["lon"].flatMap(Double.init)
            currentElevation = nil
            currentTime = nil
        case "ele" where inTrackPoint:
            readingElevation = true
            textBuffer = ""
        case "time" where inTrackPoint:
            readingTime = true
            textBuffer = ""
        case "name" where !inTrackPoint && trackName.isEmpty:
            readingName = true
            textBuffer = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard readingElevation || readingTime || readingName else { return }
        textBuffer += string
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        switch elementName {
        case "trkpt":
            if let latitude = currentLatitude,
               let longitude = currentLongitude,
               let time = currentTime {
                points.append(TrackPoint(latitude: latitude,
                                         longitude: longitude,
                                         elevation: currentElevation,
                                         time: time))
            }
            inTrackPoint = false
            currentLatitude = nil
            currentLongitude = nil
            currentElevation = nil
            currentTime = nil
        case "ele" where readingElevation:
            currentElevation = Double(textBuffer.trimmingCharacters(in: .whitespacesAndNewlines))
            readingElevation = false
            textBuffer = ""
        case "time" where readingTime:
            currentTime = GPXTimestamp.date(from: textBuffer.trimmingCharacters(in: .whitespacesAndNewlines))
            readingTime = false
            textBuffer = ""
        case "name" where readingName:
            trackName = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            readingName = false
            textBuffer = ""
        default:
            break
        }
    }
}
