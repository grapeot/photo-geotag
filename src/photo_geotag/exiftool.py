"""Thin wrapper around the `exiftool` binary."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
from datetime import datetime
from pathlib import Path

from .errors import ExiftoolNotFoundError, PhotoGeotagError

EXIF_DATE_FMT = "%Y:%m:%d %H:%M:%S"


def exiftool_bin() -> str:
    exe = os.environ.get("PHOTO_GEOTAG_EXIFTOOL", "exiftool")
    found = shutil.which(exe) or (exe if os.path.isfile(exe) else None)
    if not found:
        raise ExiftoolNotFoundError(f"exiftool not found (looked for {exe!r})")
    return found


def _run(args: list[str]) -> str:
    proc = subprocess.run(
        args, capture_output=True, text=True, check=False
    )
    if proc.returncode != 0:
        raise PhotoGeotagError(
            f"exiftool failed ({proc.returncode}): {proc.stderr.strip() or proc.stdout.strip()}"
        )
    return proc.stdout


def read_capture_times(files: list[Path]) -> dict[str, datetime]:
    """Return {path_str: naive-local DateTimeOriginal} for files that have one."""
    if not files:
        return {}
    out = _run(
        [exiftool_bin(), "-j", "-n", "-DateTimeOriginal", "-d", EXIF_DATE_FMT, *map(str, files)]
    )
    result: dict[str, datetime] = {}
    for item in json.loads(out or "[]"):
        src = item.get("SourceFile")
        dt = item.get("DateTimeOriginal")
        if src and isinstance(dt, str):
            try:
                result[src] = datetime.strptime(dt, EXIF_DATE_FMT)
            except ValueError:
                continue
    return result


def _hemi(value: float, pos: str, neg: str) -> str:
    return pos if value >= 0 else neg


def write_gps(path: Path, lat: float, lon: float, ele: float | None) -> None:
    args = [
        exiftool_bin(),
        "-overwrite_original",
        f"-GPSLatitude={abs(lat)}",
        f"-GPSLatitudeRef={_hemi(lat, 'N', 'S')}",
        f"-GPSLongitude={abs(lon)}",
        f"-GPSLongitudeRef={_hemi(lon, 'E', 'W')}",
    ]
    if ele is not None:
        args += [f"-GPSAltitude={abs(ele)}", f"-GPSAltitudeRef={0 if ele >= 0 else 1}"]
    args.append(str(path))
    _run(args)


def read_gps(files: list[Path]) -> dict[str, tuple[float, float] | None]:
    """Return {path_str: (lat, lon)} or None when GPS is absent."""
    if not files:
        return {}
    out = _run(
        [
            exiftool_bin(),
            "-j",
            "-n",
            "-GPSLatitude",
            "-GPSLongitude",
            "-GPSLatitudeRef",
            "-GPSLongitudeRef",
            *map(str, files),
        ]
    )
    result: dict[str, tuple[float, float] | None] = {}
    for item in json.loads(out or "[]"):
        src = item.get("SourceFile")
        if not src:
            continue
        lat = item.get("GPSLatitude")
        lon = item.get("GPSLongitude")
        if not isinstance(lat, (int, float)) or not isinstance(lon, (int, float)):
            result[src] = None
            continue
        if str(item.get("GPSLatitudeRef", "N")).upper().startswith("S"):
            lat = -abs(lat)
        if str(item.get("GPSLongitudeRef", "E")).upper().startswith("W"):
            lon = -abs(lon)
        result[src] = (float(lat), float(lon))
    return result
