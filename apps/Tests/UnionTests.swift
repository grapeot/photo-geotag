import XCTest

final class TrackUnionTests: XCTestCase {

    private func point(_ offset: TimeInterval, lat: Double = 1, lon: Double = 1) -> TrackPoint {
        TrackPoint(latitude: lat, longitude: lon, elevation: nil,
                   time: Date(timeIntervalSince1970: 1_700_000_000 + offset))
    }

    func testMergeConcatenatesAndOrdersByTime() {
        let first = GPXTrack(name: "A", points: [point(0), point(30), point(60)])
        let second = GPXTrack(name: "B", points: [point(10), point(40)])
        let merged = TrackUnion.merge([first, second])
        XCTAssertEqual(merged.count, 5)
        XCTAssertEqual(merged.map(\.time), merged.map(\.time).sorted())
        XCTAssertEqual(merged.first?.time.timeIntervalSince1970 ?? 0, 1_700_000_000, accuracy: 1)
    }

    func testSegmentsSplitAtLargeGap() {
        let points = [point(0), point(10), point(3600), point(3610)]
        let segments = GPXWriter.segments(from: points, maxGap: 1800)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].count, 2)
        XCTAssertEqual(segments[1].count, 2)
    }

    func testSegmentsNilGapYieldsSingleSegment() {
        let points = [point(0), point(10_000)]
        XCTAssertEqual(GPXWriter.segments(from: points, maxGap: nil).count, 1)
    }

    func testSegmentedDocumentRoundTripsAllPoints() {
        let points = [point(0), point(10), point(3600), point(3610)]
        let document = GPXWriter.document(name: "Photo Track", points: points, segmentGap: 1800)
        XCTAssertEqual(document.components(separatedBy: "<trkseg>").count - 1, 2)
        guard let parsed = GPXParser.parse(data: Data(document.utf8)) else {
            return XCTFail("Expected the segmented document to parse")
        }
        XCTAssertEqual(parsed.points.count, 4)
        XCTAssertEqual(parsed.points.map(\.time), points.map(\.time))
    }
}
