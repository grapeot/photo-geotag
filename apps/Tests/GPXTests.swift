import XCTest

final class GPXFormatTests: XCTestCase {

    func testDocumentRoundTripsThroughParser() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let points = [
            TrackPoint(latitude: 37.7749, longitude: -122.4194, elevation: 12.5, time: start),
            TrackPoint(latitude: 37.7750, longitude: -122.4195, elevation: nil,
                       time: start.addingTimeInterval(1)),
            TrackPoint(latitude: 37.7751, longitude: -122.4196, elevation: 13.0,
                       time: start.addingTimeInterval(2))
        ]

        let document = GPXWriter.document(name: "Photo Track", points: points)
        guard let parsed = GPXParser.parse(data: Data(document.utf8)) else {
            return XCTFail("Expected the written document to parse")
        }

        XCTAssertEqual(parsed.points.count, points.count)
        for (lhs, rhs) in zip(parsed.points, points) {
            XCTAssertEqual(lhs.latitude, rhs.latitude, accuracy: 1e-6)
            XCTAssertEqual(lhs.longitude, rhs.longitude, accuracy: 1e-6)
            XCTAssertEqual(lhs.elevation, rhs.elevation)
            XCTAssertEqual(lhs.time.timeIntervalSince1970, rhs.time.timeIntervalSince1970, accuracy: 1)
        }
    }

    func testTimestampParsesWithAndWithoutFractionalSeconds() {
        let plain = GPXTimestamp.date(from: "2023-11-14T22:13:20Z")
        let fractional = GPXTimestamp.date(from: "2023-11-14T22:13:20.500Z")
        XCTAssertNotNil(plain)
        XCTAssertNotNil(fractional)
        XCTAssertEqual(plain!.timeIntervalSince1970, 1_700_000_000, accuracy: 1)
        XCTAssertEqual(fractional!.timeIntervalSince1970, 1_700_000_000.5, accuracy: 0.01)
    }

    func testTimestampFormatsAsUTC() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(GPXTimestamp.string(from: date), "2023-11-14T22:13:20Z")
    }
}

final class GPXRecoveryTests: XCTestCase {

    func testRescuesPartialFileMissingClosingTags() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        // A file as it exists mid-recording: prologue plus a couple of points,
        // with no closing </trkseg></trk></gpx>.
        var partial = GPXWriter.documentStart(name: "Photo Track", time: start)
        partial += GPXWriter.trackPoint(TrackPoint(latitude: 1.0, longitude: 2.0,
                                                   elevation: nil, time: start))
        partial += GPXWriter.trackPoint(TrackPoint(latitude: 1.1, longitude: 2.1,
                                                   elevation: nil, time: start.addingTimeInterval(5)))

        guard let track = GPXRecovery.rescuedTrack(fromPartial: Data(partial.utf8)) else {
            return XCTFail("Expected a partial recording to be recoverable")
        }
        XCTAssertEqual(track.points.count, 2)
        XCTAssertEqual(track.startDate?.timeIntervalSince1970 ?? 0, 1_700_000_000, accuracy: 1)
        XCTAssertEqual(track.duration, 5, accuracy: 1)
    }

    func testReturnsNilWhenNoPointsRecorded() {
        let partial = GPXWriter.documentStart(name: "Photo Track", time: Date())
        XCTAssertNil(GPXRecovery.rescuedTrack(fromPartial: Data(partial.utf8)))
    }

    func testAlreadyClosedDocumentIsUnchanged() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let document = GPXWriter.document(name: "Photo Track", points: [
            TrackPoint(latitude: 3.0, longitude: 4.0, elevation: nil, time: start)
        ])
        let track = GPXRecovery.rescuedTrack(fromPartial: Data(document.utf8))
        XCTAssertEqual(track?.points.count, 1)
    }

    func testRecoversMultiSegmentPartial() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        // A resumed outing: points, a segment break, then more points, still
        // missing the closing tags.
        var partial = GPXWriter.documentStart(name: "Photo Track", time: start)
        partial += GPXWriter.trackPoint(TrackPoint(latitude: 1.0, longitude: 2.0,
                                                   elevation: nil, time: start))
        partial += GPXWriter.segmentBreak
        partial += GPXWriter.trackPoint(TrackPoint(latitude: 1.5, longitude: 2.5,
                                                   elevation: nil, time: start.addingTimeInterval(3600)))

        guard let track = GPXRecovery.rescuedTrack(fromPartial: Data(partial.utf8)) else {
            return XCTFail("Expected a resumed partial to be recoverable")
        }
        XCTAssertEqual(track.points.count, 2)
        XCTAssertEqual(track.duration, 3600, accuracy: 1)
    }
}
