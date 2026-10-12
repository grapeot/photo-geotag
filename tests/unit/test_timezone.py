"""Timezone parsing and conversion."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest

from photo_geotag.errors import UsageError
from photo_geotag.timeutil import (
    format_offset,
    geotime_expr,
    local_to_utc,
    parse_tz_offset,
)


@pytest.mark.parametrize(
    ("text", "hours"),
    [("+08:00", 8), ("-05:00", -5), ("-05:30", -5.5), ("+00:00", 0), ("Z", 0), ("+8", 8)],
)
def test_parse_tz_offset(text, hours):
    offset = parse_tz_offset(text)
    assert offset.utcoffset(None) == timedelta(hours=hours)


@pytest.mark.parametrize("text", ["", "abc", "+25:00", "+08:99", "+08:00:00", "+1:2:3"])
def test_parse_tz_offset_invalid(text):
    with pytest.raises(UsageError):
        parse_tz_offset(text)


def test_format_offset_round_trip():
    assert format_offset(parse_tz_offset("+08:00")) == "+08:00"
    assert format_offset(parse_tz_offset("-05:30")) == "-05:30"


def test_local_to_utc_plus_eight():
    local = datetime(2026, 5, 10, 15, 0, 0)
    utc = local_to_utc(local, parse_tz_offset("+08:00"))
    assert utc == datetime(2026, 5, 10, 7, 0, 0, tzinfo=UTC)
    assert utc.tzinfo == UTC


def test_local_to_utc_minus_five():
    local = datetime(2026, 5, 10, 15, 0, 0)
    utc = local_to_utc(local, parse_tz_offset("-05:00"))
    assert utc == datetime(2026, 5, 10, 20, 0, 0, tzinfo=UTC)


def test_geotime_expr():
    assert geotime_expr(parse_tz_offset("+08:00")) == (
        "-Geotime<${DateTimeOriginal}+08:00"
    )
