"""Shared helpers for the photo-geotag test suite."""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import pytest

EXIFTOOL = "exiftool"

requires_exiftool = pytest.mark.skipif(
    shutil.which(EXIFTOOL) is None, reason="exiftool is not on PATH"
)

FIXTURES = Path(__file__).parent / "fixtures"


def make_jpeg(
    path: str | Path, date_time_original: str | None = None
) -> Path:
    """Create a tiny synthetic JPEG; optionally stamp ``DateTimeOriginal``."""
    from PIL import Image

    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    Image.new("RGB", (4, 4), (180, 180, 180)).save(p, "JPEG", quality=85)
    if date_time_original is not None:
        set_capture_time(p, date_time_original)
    return p


def _exiftool(args: list[str]) -> None:
    subprocess.run(
        [EXIFTOOL, "-overwrite_original", *args],
        check=True,
        capture_output=True,
    )


def set_capture_time(path: str | Path, value: str) -> None:
    _exiftool([f"-DateTimeOriginal={value}", str(path)])


def set_gps(path: str | Path, lat: float, lon: float) -> None:
    _exiftool(
        [
            f"-GPSLatitude={abs(lat)}",
            f"-GPSLatitudeRef={'N' if lat >= 0 else 'S'}",
            f"-GPSLongitude={abs(lon)}",
            f"-GPSLongitudeRef={'E' if lon >= 0 else 'W'}",
            str(path),
        ]
    )


def clear_gps(path: str | Path) -> None:
    _exiftool(["-GPS:all=", str(path)])
