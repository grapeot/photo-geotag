"""Render a GPX track or a proposal file to PNG (and optional self-contained HTML)."""

from __future__ import annotations

import base64
import html
import json
from pathlib import Path

from . import gpx as gpx_module
from .errors import UsageError
from .safety import assert_safe_path

Point = tuple[float, float]


def _load_pyplot():
    try:
        import matplotlib

        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError as exc:  # pragma: no cover - depends on install
        raise UsageError(
            "matplotlib is required for viz; install the package dependencies"
        ) from exc
    return plt


def _plot(
    tracks: list[list[Point]],
    proposed: list[tuple[Point, str | None]],
    contested: list[Point],
    out_png: Path,
    title: str,
) -> None:
    plt = _load_pyplot()
    fig, ax = plt.subplots(figsize=(8.0, 6.0))

    for track in tracks:
        lons = [p[1] for p in track]
        lats = [p[0] for p in track]
        ax.plot(lons, lats, color="#2b6cb0", linewidth=1.5, marker="o", markersize=3,
                label="track")

    if proposed:
        lons = [p[0][1] for p in proposed]
        lats = [p[0][0] for p in proposed]
        ax.scatter(lons, lats, color="#2f855a", marker="o", s=36, zorder=3,
                   label="proposed")
        for (lat, lon), label in proposed:
            if label:
                ax.annotate(label, (lon, lat), fontsize=8, xytext=(4, 4),
                            textcoords="offset points")

    if contested:
        lons = [p[1] for p in contested]
        lats = [p[0] for p in contested]
        ax.scatter(lons, lats, color="#c53030", marker="x", s=48, zorder=3,
                   label="contested")

    ax.set_xlabel("longitude")
    ax.set_ylabel("latitude")
    ax.set_title(title)
    ax.grid(True, linewidth=0.3, alpha=0.5)
    ax.margins(0.15)
    handles, _labels = ax.get_legend_handles_labels()
    if handles:
        ax.legend(loc="best", fontsize=8)
    fig.tight_layout()
    out_png.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out_png, dpi=120)
    plt.close(fig)


def _write_html(out_html: Path, png_path: Path, title: str, summary: str) -> None:
    encoded = base64.b64encode(png_path.read_bytes()).decode("ascii")
    document = (
        "<!doctype html>\n"
        '<html lang="en">\n<head>\n<meta charset="utf-8">\n'
        f"<title>{html.escape(title)}</title>\n"
        "</head>\n<body>\n"
        f"<h1>{html.escape(title)}</h1>\n"
        f"<p>{html.escape(summary)}</p>\n"
        f'<img alt="{html.escape(title)}" src="data:image/png;base64,{encoded}">\n'
        "</body>\n</html>\n"
    )
    out_html.parent.mkdir(parents=True, exist_ok=True)
    out_html.write_text(document, encoding="utf-8")


def render_gpx(
    gpx_path: str | Path,
    out_png: str | Path,
    html_path: str | Path | None = None,
) -> Path:
    track_path = assert_safe_path(gpx_path)
    points = gpx_module.parse_gpx(track_path)
    if not points:
        raise UsageError(f"no trackpoints found in {track_path}")

    png = assert_safe_path(out_png)
    _plot([[ (p.lat, p.lon) for p in points ]], [], [], png, "GPX track")
    if html_path is not None:
        _write_html(
            assert_safe_path(html_path), png, "GPX track", f"{len(points)} trackpoints"
        )
    return png


def _records_from_mapping(mapping_path: Path) -> list[dict]:
    records: list[dict] = []
    with mapping_path.open("r", encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError as exc:
                raise UsageError(
                    f"{mapping_path} line {line_number}: invalid JSON"
                ) from exc
            if isinstance(obj, dict):
                records.append(obj)
    return records


def render_records(
    records: list,
    out_png: str | Path,
    html_path: str | Path | None = None,
) -> Path:
    """Render proposal records (MappingRecord objects or plain dicts)."""
    normalized = [
        r.to_dict() if hasattr(r, "to_dict") else dict(r) for r in records
    ]
    proposed: list[tuple[Point, str | None]] = []
    contested = 0
    for record in normalized:
        if record.get("status") == "contested":
            contested += 1
            continue
        lat = record.get("latitude")
        lon = record.get("longitude")
        if isinstance(lat, (int, float)) and isinstance(lon, (int, float)):
            proposed.append(((float(lat), float(lon)), record.get("place_name")))

    png = assert_safe_path(out_png)
    _plot([], proposed, [], png, "Location proposal")
    if html_path is not None:
        _write_html(
            assert_safe_path(html_path),
            png,
            "Location proposal",
            f"{len(proposed)} proposed, {contested} contested",
        )
    return png


def render_mapping(
    mapping_path: str | Path,
    out_png: str | Path,
    html_path: str | Path | None = None,
) -> Path:
    path = assert_safe_path(mapping_path)
    records = _records_from_mapping(path)
    return render_records(records, out_png, html_path)


def viz(
    input_path: str | Path,
    out_png: str | Path,
    html_path: str | Path | None = None,
) -> Path:
    """Dispatch on the input suffix: `.gpx` -> track, `.jsonl` -> proposal."""
    suffix = Path(input_path).suffix.lower()
    if suffix == ".gpx":
        return render_gpx(input_path, out_png, html_path)
    if suffix in {".jsonl", ".ndjson"}:
        return render_mapping(input_path, out_png, html_path)
    raise UsageError(
        f"unsupported viz input {input_path!r} (expected .gpx or .jsonl)"
    )
