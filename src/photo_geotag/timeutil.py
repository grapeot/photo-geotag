"""Timezone offset parsing and conversion helpers.

The photo wall-clock time (`DateTimeOriginal`) carries no offset. The `--tz-offset`
value states the offset the camera clock was set to, so a local wall-clock timestamp
is converted to UTC by subtracting that offset. All matching is done in UTC, which
keeps results independent of the host machine timezone.
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta, timezone

from .errors import UsageError

_HOURS_MAX = 23
_MINUTES_MAX = 59


def parse_tz_offset(text: str) -> timezone:
    """Parse ``+08:00`` / ``-05:30`` / ``Z`` into a ``timezone``.

    Raises ``UsageError`` for anything malformed.
    """
    if text is None:
        raise UsageError("missing timezone offset")
    raw = text.strip()
    if not raw:
        raise UsageError("empty timezone offset")
    if raw.upper() in {"Z", "UTC"}:
        return UTC

    sign = 1
    if raw[0] in "+-":
        sign = -1 if raw[0] == "-" else 1
        raw = raw[1:]

    parts = raw.split(":")
    if len(parts) == 1:
        hh, mm = parts[0], "0"
    elif len(parts) == 2:
        hh, mm = parts
    else:
        raise UsageError(f"invalid timezone offset {text!r} (expected +HH:MM)")

    try:
        hours = int(hh)
        minutes = int(mm)
    except ValueError as exc:
        raise UsageError(f"invalid timezone offset {text!r} (expected +HH:MM)") from exc

    if not (0 <= hours <= _HOURS_MAX and 0 <= minutes <= _MINUTES_MAX):
        raise UsageError(f"timezone offset out of range: {text!r}")

    return timezone(sign * timedelta(hours=hours, minutes=minutes))


def format_offset(offset: timezone) -> str:
    """Render a ``timezone`` back into ``+HH:MM`` form."""
    delta = offset.utcoffset(None) or timedelta(0)
    total_minutes = int(delta.total_seconds()) // 60
    sign = "+" if total_minutes >= 0 else "-"
    hours, minutes = divmod(abs(total_minutes), 60)
    return f"{sign}{hours:02d}:{minutes:02d}"


def local_to_utc(local_naive: datetime, offset: timezone) -> datetime:
    """Interpret a naive local wall-clock time in ``offset`` and return UTC."""
    if local_naive.tzinfo is not None:
        local_naive = local_naive.replace(tzinfo=None)
    return local_naive.replace(tzinfo=offset).astimezone(UTC)


def geotime_expr(offset: timezone) -> str:
    """The exiftool argument form for a photo offset: ``-Geotime<${DateTimeOriginal}+08:00``."""
    return f"-Geotime<${{DateTimeOriginal}}{format_offset(offset)}"
