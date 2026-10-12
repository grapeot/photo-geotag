"""Anchor table (CSV) parsing and per-date resolution."""

from __future__ import annotations

import csv
from collections import defaultdict
from dataclasses import dataclass
from datetime import date, datetime
from pathlib import Path

from .errors import UsageError

REQUIRED_COLUMNS = ("date", "latitude", "longitude")


@dataclass(frozen=True)
class Anchor:
    """A single `date -> (latitude, longitude, place_name)` row."""

    date: date
    latitude: float
    longitude: float
    place_name: str | None


@dataclass
class AnchorTable:
    """Anchors grouped by date. A date with more than one row is contested."""

    unique: dict[date, Anchor]
    contested: dict[date, list[Anchor]]

    def lookup(self, when: date) -> Anchor | None:
        return self.unique.get(when)

    def is_contested(self, when: date) -> bool:
        return when in self.contested


def _parse_date(raw: str, row_number: int) -> date:
    try:
        return datetime.strptime(raw.strip(), "%Y-%m-%d").date()
    except ValueError as exc:
        raise UsageError(
            f"anchor row {row_number}: invalid date {raw!r} (expected YYYY-MM-DD)"
        ) from exc


def _parse_coord(raw: str, field: str, row_number: int) -> float:
    try:
        return float(raw)
    except (TypeError, ValueError) as exc:
        raise UsageError(f"anchor row {row_number}: invalid {field} {raw!r}") from exc


def parse_anchors(path: str | Path) -> list[Anchor]:
    """Parse an anchor CSV. Extra columns are ignored; header row is required."""
    p = Path(path).expanduser()
    try:
        handle = p.open("r", encoding="utf-8-sig", newline="")
    except OSError as exc:
        raise UsageError(f"cannot read anchor table {p}: {exc}") from exc

    with handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames is None:
            raise UsageError(f"anchor table {p} is empty")

        present = {(name or "").strip().lower() for name in reader.fieldnames}
        missing = [col for col in REQUIRED_COLUMNS if col not in present]
        if missing:
            raise UsageError(
                f"anchor table {p} is missing required column(s): {', '.join(missing)}"
            )

        anchors: list[Anchor] = []
        for row_number, row in enumerate(reader, start=2):
            values = {(k or "").strip().lower(): (v or "").strip() for k, v in row.items()}
            if not any(values.values()):
                continue

            when = _parse_date(values.get("date", ""), row_number)
            latitude = _parse_coord(values.get("latitude", ""), "latitude", row_number)
            longitude = _parse_coord(values.get("longitude", ""), "longitude", row_number)
            if not (-90.0 <= latitude <= 90.0):
                raise UsageError(f"anchor row {row_number}: latitude out of range: {latitude}")
            if not (-180.0 <= longitude <= 180.0):
                raise UsageError(
                    f"anchor row {row_number}: longitude out of range: {longitude}"
                )

            anchors.append(
                Anchor(when, latitude, longitude, values.get("place_name") or None)
            )

    return anchors


def build_table(anchors: list[Anchor]) -> AnchorTable:
    """Group anchors by date, splitting unique dates from contested ones."""
    grouped: dict[date, list[Anchor]] = defaultdict(list)
    for anchor in anchors:
        grouped[anchor.date].append(anchor)

    unique: dict[date, Anchor] = {}
    contested: dict[date, list[Anchor]] = {}
    for when, items in grouped.items():
        if len(items) == 1:
            unique[when] = items[0]
        else:
            contested[when] = items
    return AnchorTable(unique=unique, contested=contested)
