"""Match each photo's capture time to a GPX track and write GPS EXIF."""

from __future__ import annotations

import shutil
from dataclasses import dataclass, field
from pathlib import Path

from . import exiftool, gpx
from .errors import UsageError
from .photos import list_photos
from .safety import assert_safe_path
from .timeutil import local_to_utc, parse_tz_offset

DEFAULT_MAX_GAP_S = 300.0


@dataclass
class MergeOutcome:
    """Result of a merge run."""

    total: int
    matched: list[tuple[Path, float, float, float | None]] = field(default_factory=list)
    skipped: list[Path] = field(default_factory=list)
    dry_run: bool = False


def merge(
    gpx_path: str | Path,
    photos_dir: str | Path,
    out_dir: str | Path | None = None,
    tz_offset: str = "+00:00",
    max_gap: float = DEFAULT_MAX_GAP_S,
    dry_run: bool = False,
) -> MergeOutcome:
    """Write GPS EXIF into photos whose capture time falls on the track."""
    track_path = assert_safe_path(gpx_path)
    photos_path = assert_safe_path(photos_dir)
    offset = parse_tz_offset(tz_offset)

    points = gpx.parse_gpx(track_path)
    if not points:
        raise UsageError(f"no trackpoints found in {track_path}")

    files = list_photos(photos_path)
    capture_times = exiftool.read_capture_times(files)

    out_path: Path | None = None
    if out_dir is not None:
        out_path = assert_safe_path(out_dir)
        if not dry_run:
            out_path.mkdir(parents=True, exist_ok=True)

    outcome = MergeOutcome(total=len(files), dry_run=dry_run)
    for photo in files:
        local = capture_times.get(str(photo))
        if local is None:
            outcome.skipped.append(photo)
            continue

        when_utc = local_to_utc(local, offset)
        hit = gpx.interpolate(points, when_utc, float(max_gap))
        if hit is None:
            outcome.skipped.append(photo)
            continue

        lat, lon, ele = hit
        target = photo
        if out_path is not None:
            target = out_path / photo.name
            if not dry_run:
                shutil.copy2(photo, target)
        if not dry_run:
            exiftool.write_gps(target, lat, lon, ele)
        outcome.matched.append((target, lat, lon, ele))

    return outcome
