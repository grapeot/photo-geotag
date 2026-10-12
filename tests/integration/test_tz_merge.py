"""Integration: timezone offset alignment is host-timezone independent."""

from __future__ import annotations

import os
import subprocess
import sys

import pytest

from photo_geotag.exiftool import read_gps
from photo_geotag.merge import merge
from tests.helpers import FIXTURES, make_jpeg, requires_exiftool

pytestmark = requires_exiftool


def test_local_1500_plus8_matches_0700z(tmp_path):
    photos = tmp_path / "photos"
    photos.mkdir()
    photo = make_jpeg(photos / "photo.jpg", "2026:05:10 15:00:00")

    outcome = merge(FIXTURES / "track.gpx", photos, tz_offset="+08:00")
    assert outcome.skipped == []

    lat, lon = read_gps([photo])[str(photo)]
    assert lat == pytest.approx(10.5)
    assert lon == pytest.approx(20.5)


@pytest.mark.parametrize("host_tz", ["America/New_York", "Asia/Tokyo", "UTC"])
def test_written_coordinate_is_host_timezone_independent(tmp_path, host_tz):
    photos = tmp_path / f"photos_{host_tz.replace('/', '_')}"
    photos.mkdir()
    photo = make_jpeg(photos / "photo.jpg", "2026:05:10 15:00:00")

    env = dict(os.environ)
    env["TZ"] = host_tz
    proc = subprocess.run(
        [
            sys.executable,
            "-m",
            "photo_geotag.cli",
            "merge",
            "--gpx",
            str(FIXTURES / "track.gpx"),
            "--photos",
            str(photos),
            "--tz-offset",
            "+08:00",
        ],
        capture_output=True,
        text=True,
        env=env,
        check=False,
    )
    assert proc.returncode == 0, proc.stderr

    lat, lon = read_gps([photo])[str(photo)]
    assert lat == pytest.approx(10.5)
    assert lon == pytest.approx(20.5)
