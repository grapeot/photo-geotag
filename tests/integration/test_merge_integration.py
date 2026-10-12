"""Integration: GPX merge writes interpolated GPS EXIF."""

from __future__ import annotations

import pytest

from photo_geotag.cli import main
from photo_geotag.errors import EXIT_OK, EXIT_PARTIAL
from photo_geotag.exiftool import read_gps
from photo_geotag.merge import merge
from tests.helpers import FIXTURES, make_jpeg, requires_exiftool

pytestmark = requires_exiftool


def test_merge_interpolates_within_track(tmp_path):
    photos = tmp_path / "photos"
    photos.mkdir()
    make_jpeg(photos / "a.jpg", "2026:05:10 06:30:00")
    make_jpeg(photos / "b.jpg", "2026:05:10 07:30:00")

    outcome = merge(FIXTURES / "track.gpx", photos)
    assert outcome.total == 2
    assert outcome.skipped == []

    gps = read_gps([photos / "a.jpg", photos / "b.jpg"])
    lat_a, lon_a = gps[str(photos / "a.jpg")]
    lat_b, lon_b = gps[str(photos / "b.jpg")]
    assert lat_a == pytest.approx(10.25)
    assert lon_a == pytest.approx(20.25)
    assert lat_b == pytest.approx(10.75)
    assert lon_b == pytest.approx(20.75)


def test_merge_out_copies_do_not_touch_originals(tmp_path):
    photos = tmp_path / "photos"
    photos.mkdir()
    source = make_jpeg(photos / "a.jpg", "2026:05:10 07:00:00")
    out = tmp_path / "tagged"

    outcome = merge(FIXTURES / "track.gpx", photos, out_dir=out)
    assert len(outcome.matched) == 1
    assert (out / "a.jpg").exists()

    tagged = read_gps([out / "a.jpg"])
    assert tagged[str(out / "a.jpg")][0] == pytest.approx(10.5)
    original = read_gps([source])
    assert original[str(source)] is None


def test_merge_partial_exit_code(tmp_path):
    photos = tmp_path / "photos"
    photos.mkdir()
    make_jpeg(photos / "inside.jpg", "2026:05:10 07:00:00")
    make_jpeg(photos / "outside.jpg", "2026:05:10 12:00:00")

    outcome = merge(FIXTURES / "track.gpx", photos)
    assert len(outcome.matched) == 1
    assert len(outcome.skipped) == 1

    code = main(["merge", "--gpx", str(FIXTURES / "track.gpx"), "--photos", str(photos)])
    assert code == EXIT_PARTIAL

    all_inside = tmp_path / "all_inside"
    all_inside.mkdir()
    make_jpeg(all_inside / "ok.jpg", "2026:05:10 07:00:00")
    code_ok = main(["merge", "--gpx", str(FIXTURES / "track.gpx"),
                    "--photos", str(all_inside)])
    assert code_ok == EXIT_OK


def test_merge_dry_run_writes_nothing(tmp_path):
    photos = tmp_path / "photos"
    photos.mkdir()
    make_jpeg(photos / "a.jpg", "2026:05:10 07:00:00")

    outcome = merge(FIXTURES / "track.gpx", photos, dry_run=True)
    assert outcome.dry_run is True
    assert outcome.skipped == []
    assert read_gps([photos / "a.jpg"])[str(photos / "a.jpg")] is None
