"""Listing candidate photo files in a staging directory."""

from __future__ import annotations

from pathlib import Path

from .errors import UsageError

# Common camera and portable-image extensions. RAW formats are included because
# exiftool writes their GPS tags safely.
IMAGE_SUFFIXES = frozenset(
    {
        ".jpg",
        ".jpeg",
        ".jpe",
        ".tif",
        ".tiff",
        ".png",
        ".heic",
        ".heif",
        ".dng",
        ".cr2",
        ".cr3",
        ".nef",
        ".nrw",
        ".arw",
        ".srf",
        ".sr2",
        ".raf",
        ".orf",
        ".rw2",
        ".pef",
        ".srw",
        ".x3f",
    }
)


def list_photos(directory: str | Path) -> list[Path]:
    """Return sorted image files directly inside ``directory`` (non-recursive)."""
    d = Path(directory)
    if not d.is_dir():
        raise UsageError(f"photos directory not found: {d}")
    return sorted(
        p for p in d.iterdir() if p.is_file() and p.suffix.lower() in IMAGE_SUFFIXES
    )
