"""Command-line entry point for photo-geotag."""

from __future__ import annotations

import argparse
import json
import sys

from . import fallback as fallback_module
from . import merge as merge_module
from . import verify as verify_module
from . import viz as viz_module
from .errors import EXIT_OK, EXIT_PARTIAL, EXIT_VERIFY, PhotoGeotagError


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="photo-geotag",
        description="Give locations to photos that lack GPS, from a track or an anchor table.",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    merge = subparsers.add_parser(
        "merge", help="write GPS EXIF from a GPX track, matched by capture time"
    )
    merge.add_argument("--gpx", required=True, help="GPX track file")
    merge.add_argument("--photos", required=True, help="directory of pre-import photos")
    merge.add_argument("--out", default=None, help="write copies here (default: in place)")
    merge.add_argument("--tz-offset", default="+00:00", help="photo wall-clock offset, e.g. +08:00")
    merge.add_argument("--max-gap", type=float, default=merge_module.DEFAULT_MAX_GAP_S,
                       help="interpolation/extrapolation window in seconds")
    merge.add_argument("--dry-run", action="store_true", help="report without writing")

    fallback = subparsers.add_parser(
        "fallback", help="build a per-photo proposal from an anchor table"
    )
    fallback.add_argument("--anchors", required=True, help="anchor CSV (date,latitude,longitude,place_name)")
    fallback.add_argument("--photos", required=True, help="directory of pre-import photos")
    fallback.add_argument("--out", required=True, help="output mapping.jsonl path")
    fallback.add_argument("--viz", default=None, help="optional map PNG path")
    fallback.add_argument("--tz-offset", default="+00:00", help="photo wall-clock offset")

    viz = subparsers.add_parser("viz", help="render a track or a proposal")
    viz.add_argument("--input", required=True, help="a .gpx track or a .jsonl proposal")
    viz.add_argument("--out", required=True, help="output map PNG path")
    viz.add_argument("--html", default=None, help="optional self-contained HTML path")

    verify = subparsers.add_parser("verify", help="read EXIF back and assert coordinates")
    verify.add_argument("--photos", required=True, help="directory of tagged photos")
    source = verify.add_mutually_exclusive_group(required=True)
    source.add_argument("--gpx", help="reference GPX track")
    source.add_argument("--mapping", help="reference mapping.jsonl proposal")
    verify.add_argument("--tolerance-deg", type=float, default=verify_module.DEFAULT_TOLERANCE_DEG)
    verify.add_argument("--tz-offset", default="+00:00", help="photo wall-clock offset (with --gpx)")

    return parser


def _print_merge(outcome: merge_module.MergeOutcome) -> None:
    verb = "would write" if outcome.dry_run else "wrote"
    print(
        f"merge: {outcome.total} photos, {len(outcome.matched)} matched, "
        f"{len(outcome.skipped)} skipped"
    )
    for path in outcome.skipped:
        print(f"  skipped: {path}", file=sys.stderr)
    if outcome.dry_run:
        print(f"dry-run: no files {verb}")


def _dispatch(args: argparse.Namespace) -> int:
    if args.command == "merge":
        outcome = merge_module.merge(
            gpx_path=args.gpx,
            photos_dir=args.photos,
            out_dir=args.out,
            tz_offset=args.tz_offset,
            max_gap=args.max_gap,
            dry_run=args.dry_run,
        )
        _print_merge(outcome)
        return EXIT_PARTIAL if outcome.skipped else EXIT_OK

    if args.command == "fallback":
        records, out = fallback_module.fallback(
            anchors_path=args.anchors,
            photos_dir=args.photos,
            out_path=args.out,
            viz_path=args.viz,
            tz_offset=args.tz_offset,
        )
        proposed = sum(1 for r in records if r.status == fallback_module.STATUS_PROPOSED)
        contested = len(records) - proposed
        print(
            f"fallback: wrote {len(records)} records to {out} "
            f"({proposed} proposed, {contested} contested)"
        )
        return EXIT_OK

    if args.command == "viz":
        path = viz_module.viz(args.input, args.out, html_path=args.html)
        print(f"viz: wrote {path}")
        return EXIT_OK

    if args.command == "verify":
        report = verify_module.build_report(
            photos_dir=args.photos,
            gpx_path=args.gpx,
            mapping_path=args.mapping,
            tolerance_deg=args.tolerance_deg,
            tz_offset=args.tz_offset,
        )
        print(json.dumps(report))
        return EXIT_OK if report["status"] == "passed" else EXIT_VERIFY

    return EXIT_OK


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return _dispatch(args)
    except PhotoGeotagError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return exc.exit_code


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
