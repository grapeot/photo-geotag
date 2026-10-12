"""Build a per-photo location proposal from an anchor table (no track)."""

from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

from . import exiftool
from .anchors import AnchorTable, build_table, parse_anchors
from .photos import list_photos
from .safety import assert_safe_path
from .timeutil import parse_tz_offset

CAPTURE_TIME_FMT = "%Y-%m-%dT%H:%M:%S"
SOURCE_ANCHOR = "anchor"
STATUS_PROPOSED = "proposed"
STATUS_CONTESTED = "contested"


@dataclass
class MappingRecord:
    """One line of `mapping.jsonl`, per docs/interface.md section 3."""

    photo_path: str
    capture_time: str
    latitude: float | None
    longitude: float | None
    source: str
    place_name: str | None
    status: str
    reason: str | None = None

    def to_dict(self) -> dict:
        record: dict = {
            "photo_path": self.photo_path,
            "capture_time": self.capture_time,
            "latitude": self.latitude,
            "longitude": self.longitude,
            "source": self.source,
            "place_name": self.place_name,
            "status": self.status,
        }
        if self.status == STATUS_CONTESTED:
            record["reason"] = self.reason or ""
        return record


def _contested(photo: Path, capture_time: str, reason: str) -> MappingRecord:
    return MappingRecord(
        photo_path=str(photo),
        capture_time=capture_time,
        latitude=None,
        longitude=None,
        source=SOURCE_ANCHOR,
        place_name=None,
        status=STATUS_CONTESTED,
        reason=reason,
    )


def build_records(
    table: AnchorTable,
    photos: list[Path],
    capture_times: dict[str, datetime],
) -> list[MappingRecord]:
    """Resolve each photo against the anchor table by its local capture date."""
    records: list[MappingRecord] = []
    for photo in photos:
        local = capture_times.get(str(photo))
        if local is None:
            records.append(
                _contested(photo, "", "no DateTimeOriginal for photo")
            )
            continue

        capture_time = local.strftime(CAPTURE_TIME_FMT)
        anchor = table.lookup(local.date())
        if anchor is not None:
            records.append(
                MappingRecord(
                    photo_path=str(photo),
                    capture_time=capture_time,
                    latitude=anchor.latitude,
                    longitude=anchor.longitude,
                    source=SOURCE_ANCHOR,
                    place_name=anchor.place_name,
                    status=STATUS_PROPOSED,
                )
            )
        elif table.is_contested(local.date()):
            records.append(
                _contested(
                    photo,
                    capture_time,
                    f"multiple anchors for date {local.date().isoformat()}",
                )
            )
        else:
            records.append(
                _contested(
                    photo,
                    capture_time,
                    f"no anchor for date {local.date().isoformat()}",
                )
            )
    return records


def write_mapping(records: list[MappingRecord], out_path: str | Path) -> Path:
    """Write records as UTF-8 JSON Lines. Returns the resolved output path."""
    target = assert_safe_path(out_path)
    target.parent.mkdir(parents=True, exist_ok=True)
    with target.open("w", encoding="utf-8") as handle:
        for record in records:
            handle.write(json.dumps(record.to_dict(), ensure_ascii=False))
            handle.write("\n")
    return target


def fallback(
    anchors_path: str | Path,
    photos_dir: str | Path,
    out_path: str | Path,
    viz_path: str | Path | None = None,
    tz_offset: str = "+00:00",
) -> tuple[list[MappingRecord], Path]:
    """Produce `mapping.jsonl` (and an optional map) from an anchor table.

    `tz_offset` is accepted for interface parity; capture dates are resolved in the
    photos' local wall-clock date, so it does not shift date assignment.
    """
    assert_safe_path(anchors_path)
    photos_path = assert_safe_path(photos_dir)
    parse_tz_offset(tz_offset)

    table = build_table(parse_anchors(anchors_path))
    files = list_photos(photos_path)
    capture_times = exiftool.read_capture_times(files)
    records = build_records(table, files, capture_times)
    out = write_mapping(records, out_path)

    if viz_path is not None:
        from . import viz as viz_module

        viz_module.render_records(records, viz_path)

    return records, out
