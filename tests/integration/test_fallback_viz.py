"""Integration: fallback proposal pipeline and visualization."""

from __future__ import annotations

import json

import pytest

from photo_geotag.cli import main
from tests.helpers import FIXTURES, make_jpeg, requires_exiftool

pytestmark = requires_exiftool

PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


def test_fallback_writes_valid_mapping(tmp_path):
    photos = tmp_path / "photos"
    photos.mkdir()
    make_jpeg(photos / "alpha.jpg", "2026:05:10 14:32:00")
    make_jpeg(photos / "orphan.jpg", "2026:05:13 09:00:00")

    mapping = tmp_path / "mapping.jsonl"
    code = main(
        [
            "fallback",
            "--anchors",
            str(FIXTURES / "anchors.csv"),
            "--photos",
            str(photos),
            "--out",
            str(mapping),
        ]
    )
    assert code == 0

    lines = [json.loads(line) for line in mapping.read_text().splitlines()]
    by_name = {line["photo_path"].split("/")[-1]: line for line in lines}
    assert by_name["alpha.jpg"]["status"] == "proposed"
    assert by_name["alpha.jpg"]["latitude"] == pytest.approx(10.5)
    assert by_name["alpha.jpg"]["place_name"] == "Alpha"
    assert by_name["orphan.jpg"]["status"] == "contested"
    assert by_name["orphan.jpg"]["latitude"] is None
    assert by_name["orphan.jpg"]["reason"] == "no anchor for date 2026-05-13"


def test_fallback_viz_outputs_png_and_html(tmp_path):
    photos = tmp_path / "photos"
    photos.mkdir()
    make_jpeg(photos / "alpha.jpg", "2026:05:10 14:32:00")

    mapping = tmp_path / "mapping.jsonl"
    png = tmp_path / "map.png"
    html = tmp_path / "map.html"
    assert main(
        [
            "fallback",
            "--anchors",
            str(FIXTURES / "anchors.csv"),
            "--photos",
            str(photos),
            "--out",
            str(mapping),
        ]
    ) == 0

    code = main(["viz", "--input", str(mapping), "--out", str(png), "--html", str(html)])
    assert code == 0
    assert png.read_bytes()[:8] == PNG_MAGIC
    assert png.stat().st_size > 0
    assert html.read_text().lstrip().lower().startswith("<!doctype html>")


def test_viz_renders_gpx_track(tmp_path):
    png = tmp_path / "track.png"
    assert main(["viz", "--input", str(FIXTURES / "track.gpx"), "--out", str(png)]) == 0
    assert png.read_bytes()[:8] == PNG_MAGIC
