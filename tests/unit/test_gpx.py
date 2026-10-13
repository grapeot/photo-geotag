"""GPX parsing and time interpolation."""

from __future__ import annotations

from datetime import UTC, datetime

from photo_geotag.gpx import TrackPoint, interpolate, parse_gpx, parse_gpx_segments
from tests.helpers import FIXTURES


def test_parse_gpx_segments_splits_at_trkseg(tmp_path):
    doc = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<gpx version="1.1" creator="t" xmlns="http://www.topografix.com/GPX/1/1">\n'
        "  <trk><trkseg>\n"
        '    <trkpt lat="10.0" lon="20.0"><time>2026-05-10T06:00:00Z</time></trkpt>\n'
        '    <trkpt lat="10.1" lon="20.1"><time>2026-05-10T06:00:10Z</time></trkpt>\n'
        "  </trkseg><trkseg>\n"
        '    <trkpt lat="10.5" lon="20.5"><time>2026-05-10T06:20:00Z</time></trkpt>\n'
        "  </trkseg></trk>\n</gpx>\n"
    )
    path = tmp_path / "seg.gpx"
    path.write_text(doc, encoding="utf-8")
    segments = parse_gpx_segments(path)
    assert [len(s) for s in segments] == [2, 1]
    # The flat parse still sees every point, in time order.
    assert len(parse_gpx(path)) == 3


def test_parse_gpx_segments_falls_back_when_no_trkseg(tmp_path):
    doc = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<gpx version="1.1" creator="t" xmlns="http://www.topografix.com/GPX/1/1">\n'
        "  <trk>\n"
        '    <trkpt lat="1.0" lon="2.0"><time>2026-05-10T06:00:00Z</time></trkpt>\n'
        "  </trk>\n</gpx>\n"
    )
    path = tmp_path / "flat.gpx"
    path.write_text(doc, encoding="utf-8")
    segments = parse_gpx_segments(path)
    assert [len(s) for s in segments] == [1]


def _p(hour: int, minute: int, lat: float, lon: float, ele: float) -> TrackPoint:
    t = datetime(2026, 5, 10, hour, minute, tzinfo=UTC)
    return TrackPoint(t, lat, lon, ele)


def test_parse_fixture_track_sorted():
    points = parse_gpx(FIXTURES / "track.gpx")
    assert len(points) == 3
    assert [p.t for p in points] == sorted(p.t for p in points)
    assert points[0].t == datetime(2026, 5, 10, 6, 0, tzinfo=UTC)
    assert (points[0].lat, points[0].lon, points[0].ele) == (10.0, 20.0, 100.0)


def test_interpolate_exact_point():
    points = [_p(6, 0, 10.0, 20.0, 100.0), _p(7, 0, 10.5, 20.5, 150.0),
              _p(8, 0, 11.0, 21.0, 200.0)]
    hit = interpolate(points, datetime(2026, 5, 10, 7, 0, tzinfo=UTC), 300)
    assert hit == (10.5, 20.5, 150.0)


def test_interpolate_midpoint():
    points = [_p(6, 0, 10.0, 20.0, 100.0), _p(8, 0, 11.0, 21.0, 200.0)]
    hit = interpolate(points, datetime(2026, 5, 10, 7, 0, tzinfo=UTC), 300)
    assert hit is not None
    lat, lon, ele = hit
    assert lat == 10.5 and lon == 20.5
    assert ele == 150.0


def test_interpolate_outside_within_gap_clamps():
    points = [_p(6, 0, 10.0, 20.0, 100.0), _p(8, 0, 11.0, 21.0, 200.0)]
    before = interpolate(points, datetime(2026, 5, 10, 5, 55, tzinfo=UTC), 300)
    after = interpolate(points, datetime(2026, 5, 10, 8, 5, tzinfo=UTC), 300)
    assert before == (10.0, 20.0, 100.0)
    assert after == (11.0, 21.0, 200.0)


def test_interpolate_outside_beyond_gap_is_none():
    points = [_p(6, 0, 10.0, 20.0, 100.0), _p(8, 0, 11.0, 21.0, 200.0)]
    assert interpolate(points, datetime(2026, 5, 10, 12, 0, tzinfo=UTC), 300) is None


def test_interpolate_single_point():
    points = [_p(7, 0, 10.5, 20.5, 150.0)]
    assert interpolate(points, datetime(2026, 5, 10, 7, 4, tzinfo=UTC), 300) == (
        10.5,
        20.5,
        150.0,
    )
    assert interpolate(points, datetime(2026, 5, 10, 9, 0, tzinfo=UTC), 300) is None


def test_interpolate_empty():
    assert interpolate([], datetime(2026, 5, 10, 7, 0, tzinfo=UTC), 300) is None
