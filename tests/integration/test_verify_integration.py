"""Integration: verify reads EXIF back and asserts against ground truth."""

from __future__ import annotations

from photo_geotag.cli import main
from photo_geotag.errors import EXIT_OK, EXIT_VERIFY
from photo_geotag.merge import merge
from photo_geotag.verify import build_report
from tests.helpers import FIXTURES, make_jpeg, requires_exiftool, set_gps

pytestmark = requires_exiftool


def test_verify_passes_after_merge(tmp_path):
    photos = tmp_path / "photos"
    photos.mkdir()
    make_jpeg(photos / "a.jpg", "2026:05:10 06:30:00")
    make_jpeg(photos / "b.jpg", "2026:05:10 07:30:00")
    merge(FIXTURES / "track.gpx", photos)

    report = build_report(photos, gpx_path=FIXTURES / "track.gpx")
    assert report["status"] == "passed"
    assert report["verified_photos"] == 2
    assert report["mismatches"] == 0
    assert report["missing_gps"] == 0

    code = main(["verify", "--photos", str(photos), "--gpx", str(FIXTURES / "track.gpx")])
    assert code == EXIT_OK


def test_verify_detects_mismatch(tmp_path):
    photos = tmp_path / "photos"
    photos.mkdir()
    photo = make_jpeg(photos / "a.jpg", "2026:05:10 07:00:00")
    merge(FIXTURES / "track.gpx", photos)
    set_gps(photo, 0.0, 0.0)

    report = build_report(photos, gpx_path=FIXTURES / "track.gpx")
    assert report["status"] == "failed"
    assert report["mismatches"] == 1

    code = main(["verify", "--photos", str(photos), "--gpx", str(FIXTURES / "track.gpx")])
    assert code == EXIT_VERIFY


def test_verify_detects_missing_gps(tmp_path):
    photos = tmp_path / "photos"
    photos.mkdir()
    make_jpeg(photos / "untagged.jpg", "2026:05:10 07:00:00")

    report = build_report(photos, gpx_path=FIXTURES / "track.gpx")
    assert report["status"] == "failed"
    assert report["missing_gps"] == 1
