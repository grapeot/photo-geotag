"""Read EXIF GPS back and compare it to expected coordinates."""

from __future__ import annotations

import json
import os
from pathlib import Path

from . import exiftool, gpx
from .errors import UsageError
from .merge import DEFAULT_MAX_GAP_S
from .photos import list_photos
from .safety import assert_safe_path
from .timeutil import local_to_utc, parse_tz_offset

DEFAULT_TOLERANCE_DEG = 0.0001


def _real(path: str | Path) -> str:
    return os.path.realpath(str(path))


def _expected_from_mapping(mapping_path: Path) -> dict[str, tuple[float, float]]:
    expected: dict[str, tuple[float, float]] = {}
    with mapping_path.open("r", encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError as exc:
                raise UsageError(
                    f"{mapping_path} line {line_number}: invalid JSON"
                ) from exc
            photo = obj.get("photo_path")
            lat = obj.get("latitude")
            lon = obj.get("longitude")
            if not photo:
                continue
            if isinstance(lat, (int, float)) and isinstance(lon, (int, float)):
                expected[_real(photo)] = (float(lat), float(lon))
            # Contested records carry no coordinates; nothing to verify.
    return expected


def _expected_from_track(
    track_path: Path, photos: list[Path], tz_offset: str, max_gap: float
) -> dict[str, tuple[float, float]]:
    offset = parse_tz_offset(tz_offset)
    points = gpx.parse_gpx(track_path)
    if not points:
        raise UsageError(f"no trackpoints found in {track_path}")

    capture_times = exiftool.read_capture_times(photos)
    expected: dict[str, tuple[float, float]] = {}
    for photo in photos:
        local = capture_times.get(str(photo))
        if local is None:
            continue
        hit = gpx.interpolate(points, local_to_utc(local, offset), max_gap)
        if hit is not None:
            expected[_real(photo)] = (hit[0], hit[1])
    return expected


def _within(
    expected: tuple[float, float], actual: tuple[float, float], tolerance: float
) -> bool:
    return (
        abs(expected[0] - actual[0]) <= tolerance
        and abs(expected[1] - actual[1]) <= tolerance
    )


def build_report(
    photos_dir: str | Path,
    gpx_path: str | Path | None = None,
    mapping_path: str | Path | None = None,
    tolerance_deg: float = DEFAULT_TOLERANCE_DEG,
    tz_offset: str = "+00:00",
    max_gap: float = DEFAULT_MAX_GAP_S,
) -> dict:
    """Scan photos and return the verification summary (docs/interface.md section 6)."""
    if (gpx_path is None) == (mapping_path is None):
        raise UsageError("verify requires exactly one of --gpx or --mapping")

    photos_path = assert_safe_path(photos_dir)
    files = list_photos(photos_path)

    if mapping_path is not None:
        expected = _expected_from_mapping(assert_safe_path(mapping_path))
    else:
        expected = _expected_from_track(
            assert_safe_path(gpx_path), files, tz_offset, max_gap
        )

    actual = exiftool.read_gps(files)

    verified = mismatches = missing_gps = 0
    for photo in files:
        target = expected.get(_real(photo))
        if target is None:
            continue
        found = actual.get(str(photo))
        if found is None:
            missing_gps += 1
        elif _within(target, found, tolerance_deg):
            verified += 1
        else:
            mismatches += 1

    status = "passed" if mismatches == 0 and missing_gps == 0 else "failed"
    return {
        "total_photos": len(files),
        "verified_photos": verified,
        "mismatches": mismatches,
        "missing_gps": missing_gps,
        "tolerance_deg": tolerance_deg,
        "status": status,
    }
