"""Fallback anchor resolution and mapping serialization."""

from __future__ import annotations

from datetime import datetime
from pathlib import Path

from photo_geotag.anchors import Anchor, build_table, parse_anchors
from photo_geotag.fallback import (
    STATUS_CONTESTED,
    STATUS_PROPOSED,
    build_records,
)
from tests.helpers import FIXTURES


def test_parse_anchors_fixture():
    anchors = parse_anchors(FIXTURES / "anchors.csv")
    assert len(anchors) == 2
    assert anchors[0].place_name == "Alpha"
    assert anchors[1].latitude == 11.25


def test_build_table_flags_duplicate_dates():
    anchors = [
        Anchor(datetime(2026, 5, 10).date(), 10.0, 20.0, "Alpha"),
        Anchor(datetime(2026, 5, 10).date(), 11.0, 21.0, "Gamma"),
        Anchor(datetime(2026, 5, 11).date(), 12.0, 22.0, "Beta"),
    ]
    table = build_table(anchors)
    assert set(table.unique) == {datetime(2026, 5, 11).date()}
    assert datetime(2026, 5, 10).date() in table.contested


def test_build_records_proposed_and_contested():
    anchors = parse_anchors(FIXTURES / "anchors.csv")
    table = build_table(anchors)
    photos = [Path("/photos/a.jpg"), Path("/photos/b.jpg")]
    times = {
        str(photos[0]): datetime(2026, 5, 10, 14, 32, 0),
        str(photos[1]): datetime(2026, 5, 13, 9, 0, 0),
    }
    records = build_records(table, photos, times)
    by_path = {r.photo_path: r for r in records}

    proposed = by_path["/photos/a.jpg"]
    assert proposed.status == STATUS_PROPOSED
    assert proposed.capture_time == "2026-05-10T14:32:00"
    assert (proposed.latitude, proposed.longitude) == (10.5, 20.5)
    assert proposed.place_name == "Alpha"
    assert "reason" not in proposed.to_dict()

    contested = by_path["/photos/b.jpg"]
    assert contested.status == STATUS_CONTESTED
    assert contested.latitude is None and contested.longitude is None
    assert contested.to_dict()["reason"] == "no anchor for date 2026-05-13"


def test_build_records_contested_duplicate_date():
    anchors = parse_anchors(FIXTURES / "anchors_contested.csv")
    table = build_table(anchors)
    photos = [Path("/photos/c.jpg")]
    times = {str(photos[0]): datetime(2026, 5, 10, 8, 0, 0)}
    records = build_records(table, photos, times)
    assert records[0].status == STATUS_CONTESTED
    assert records[0].reason == "multiple anchors for date 2026-05-10"


def test_build_records_missing_capture_time():
    table = build_table(parse_anchors(FIXTURES / "anchors.csv"))
    photos = [Path("/photos/d.jpg")]
    records = build_records(table, photos, {})
    assert records[0].status == STATUS_CONTESTED
    assert records[0].capture_time == ""
