"""CLI parsing and exit-code dispatch."""

from __future__ import annotations

import pytest

from photo_geotag.cli import build_parser, main
from photo_geotag.errors import EXIT_SAFETY, EXIT_USAGE


def test_merge_defaults():
    args = build_parser().parse_args(["merge", "--gpx", "t.gpx", "--photos", "p"])
    assert args.tz_offset == "+00:00"
    assert args.max_gap == 300.0
    assert args.dry_run is False
    assert args.out is None


def test_fallback_requires_out():
    with pytest.raises(SystemExit) as excinfo:
        build_parser().parse_args(["fallback", "--anchors", "a.csv", "--photos", "p"])
    assert excinfo.value.code == 2


def test_viz_requires_input_and_out():
    with pytest.raises(SystemExit):
        build_parser().parse_args(["viz", "--out", "map.png"])


def test_verify_source_is_mutually_exclusive():
    parser = build_parser()
    with pytest.raises(SystemExit):
        parser.parse_args(["verify", "--photos", "p"])
    with pytest.raises(SystemExit):
        parser.parse_args(
            ["verify", "--photos", "p", "--gpx", "t.gpx", "--mapping", "m.jsonl"]
        )
    args = parser.parse_args(["verify", "--photos", "p", "--gpx", "t.gpx"])
    assert args.gpx == "t.gpx"
    assert args.tolerance_deg == 0.0001


def test_missing_required_flag_is_usage_error():
    with pytest.raises(SystemExit) as excinfo:
        build_parser().parse_args(["merge", "--photos", "p"])
    assert excinfo.value.code == 2


def test_main_invalid_timezone_returns_usage_error():
    code = main(["merge", "--gpx", "/tmp/t.gpx", "--photos", "/tmp/p",
                 "--tz-offset", "not-an-offset"])
    assert code == EXIT_USAGE


def test_main_rejects_photoslibrary_path():
    code = main(["merge", "--gpx", "/tmp/Lib.photoslibrary/t.gpx",
                 "--photos", "/tmp/p"])
    assert code == EXIT_SAFETY
