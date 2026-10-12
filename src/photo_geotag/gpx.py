"""Parse GPX 1.1 tracks and interpolate positions by time."""

from __future__ import annotations

import xml.etree.ElementTree as ET
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path


@dataclass(frozen=True)
class TrackPoint:
    t: datetime  # timezone-aware, UTC
    lat: float
    lon: float
    ele: float | None


def _parse_iso_utc(text: str) -> datetime:
    s = text.strip()
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    dt = datetime.fromisoformat(s)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=UTC)
    return dt.astimezone(UTC)


def parse_gpx(path: str | Path) -> list[TrackPoint]:
    """Parse all `<trkpt>` elements into a time-sorted list. Namespace-agnostic."""
    root = ET.parse(str(path)).getroot()
    points: list[TrackPoint] = []
    for el in root.iter():
        if el.tag.split("}")[-1] != "trkpt":
            continue
        lat = el.get("lat")
        lon = el.get("lon")
        if lat is None or lon is None:
            continue
        t: datetime | None = None
        ele: float | None = None
        for child in el:
            tag = child.tag.split("}")[-1]
            if tag == "time" and child.text:
                t = _parse_iso_utc(child.text)
            elif tag == "ele" and child.text:
                try:
                    ele = float(child.text.strip())
                except ValueError:
                    ele = None
        if t is not None:
            points.append(TrackPoint(t, float(lat), float(lon), ele))
    points.sort(key=lambda p: p.t)
    return points


def interpolate(
    points: list[TrackPoint], when: datetime, max_gap_s: float
) -> tuple[float, float, float | None] | None:
    """Return (lat, lon, ele) at `when`, or None if outside the track beyond max_gap_s."""
    if not points:
        return None
    if when.tzinfo is None:
        when = when.replace(tzinfo=UTC)

    first, last = points[0], points[-1]
    if when < first.t:
        if (first.t - when).total_seconds() <= max_gap_s:
            return first.lat, first.lon, first.ele
        return None
    if when > last.t:
        if (when - last.t).total_seconds() <= max_gap_s:
            return last.lat, last.lon, last.ele
        return None

    # find bracketing pair
    prev = points[0]
    for cur in points[1:]:
        if cur.t >= when:
            span = (cur.t - prev.t).total_seconds()
            if span <= 0:
                return cur.lat, cur.lon, cur.ele
            frac = (when - prev.t).total_seconds() / span
            lat = prev.lat + (cur.lat - prev.lat) * frac
            lon = prev.lon + (cur.lon - prev.lon) * frac
            if prev.ele is not None and cur.ele is not None:
                ele = prev.ele + (cur.ele - prev.ele) * frac
            else:
                ele = prev.ele if prev.ele is not None else cur.ele
            return lat, lon, ele
        prev = cur
    return last.lat, last.lon, last.ele
