# photo-geotag

`photo-geotag` is a small cross-platform toolkit that assigns geographic coordinates to photos that lack GPS metadata, allowing them to be indexed, organized, and visualized on a map.

It is **not** a fitness application and does not collect, process, or store health or workout data.

---

## Overview

Many dedicated digital and analog cameras do not record GPS coordinates. `photo-geotag` provides two location sources to resolve missing locations:

1. **Recorded GPS Track (GPX)**: Matches trackpoints to photo capture timestamps. Precise to the second for individual photos.
2. **Fallback Location Table**: Matches photo capture dates to daily anchor coordinates (`date -> place`) when no track exists. Coarse to the day.

Geotagging must always be performed on **pre-import copies** of photo files *before* adding them to an image management library. The toolkit never modifies existing photo library bundles (such as `.photoslibrary`).

---

## Components

The project consists of four decoupled components:

1. **Watch App (`watchOS`)**: Records a GPS track during an outing without creating a workout record. It uses an `HKWorkoutSession` exclusively to retain background execution and GPS sensor access, and discards the session upon completion so that no workout appears in Apple Fitness or Health. Trackpoints are written incrementally to local storage. Features a single start/stop control, bilingual localization (English and Chinese) matching system preferences, and support for light and dark appearance.
2. **iPhone App (`iOS`)**: Companion application within the same Xcode project. Receives completed tracks from the watch over `WatchConnectivity`, stores them locally, visualizes sessions on a map, and exports GPX files via the system share sheet, AirDrop, or the Files app. Features identical bilingual localization and appearance adaptation.
3. **CLI (`photo-geotag`)**: Python package under `src/photo_geotag/` with thin executable entrypoints under `scripts/`. Provides commands to merge GPX tracks into EXIF metadata, compute fallback mappings from anchor tables, render map visualizations, and verify injected coordinates.
4. **Agent Skill (`skills/photo_geotag.md`)**: An automated agent skill defining acceptance criteria, operational boundaries, and verification routines for autonomous workflows.

---

## Architecture at a Glance

The toolkit is divided into two decoupled layers:

- **Capture Layer (Apple Watch & iPhone)**: Device-specific. Handles sensor logging and GPX export.
- **Merge Layer (CLI)**: Device-agnostic. Operates on standard GPX files from any source (the companion app, third-party loggers, or dedicated handheld units) as well as tabular fallback files.

```
[ Watch App ] --WatchConnectivity--> [ iPhone App ] --GPX Export--> [ GPX File ]
                                                                          |
                                                                          v
[ Pre-Import Photos ] + [ GPX Track / Anchor Table ] ----------> [ photo-geotag CLI ]
                                                                          |
                                                                          v
                                                          [ Geotagged Photo Files ]
```

---

## CLI Installation

### Prerequisites

- Python 3.11 or later
- [`uv`](https://github.com/astral-sh/uv) (recommended) or `pip`
- [`exiftool`](https://exiftool.org/) installed and available on system `$PATH`

### Setup

```bash
# Clone the repository
git clone https://github.com/example/photo-geotag.git
cd photo-geotag

# Create and activate a virtual environment
uv venv
source .venv/bin/activate

# Install dependencies and editable CLI
uv pip install -e .
```

Verify that `exiftool` is accessible:

```bash
exiftool -ver
```

---

## CLI Usage

The `photo-geotag` CLI provides four subcommands: `merge`, `fallback`, `viz`, and `verify`.

### 1. `merge`

Writes GPS EXIF tags into a directory of photos by matching their `DateTimeOriginal` against a recorded GPX track. Operations are delegated to `exiftool`.

Because camera clocks record local wall-clock time without timezone metadata, the timezone offset must be specified when the shooting timezone differs from the host machine's timezone.

```bash
# Basic merge with local timezone assumption
photo-geotag merge --gpx /path/to/track.gpx --photos /path/to/photos

# Merge with explicit timezone offset for photos taken in UTC+8
photo-geotag merge --gpx /path/to/track.gpx --photos /path/to/photos --tz-offset "+08:00"
```

### 2. `fallback`

When no GPS track exists, `fallback` reads an anchor table (mapping dates to locations) and photo metadata to generate a per-photo proposal file (`mapping.jsonl`). It can optionally emit a preview map.

```bash
# Generate mapping proposal
photo-geotag fallback --anchors /path/to/anchors.csv --photos /path/to/photos --out /path/to/mapping.jsonl

# Generate mapping proposal along with a visual overview
photo-geotag fallback --anchors /path/to/anchors.csv --photos /path/to/photos --out /path/to/mapping.jsonl --viz /path/to/proposal_map.png
```

Anchor table format (`anchors.csv`):

```csv
date,latitude,longitude,place_name
2026-05-10,37.7749,-122.4194,San Francisco
2026-05-11,36.6002,-121.8947,Monterey
```

### 3. `viz`

Renders a geographic visualization of a recorded track or a generated mapping proposal to an image file, with optional interactive HTML output.

```bash
# Render static PNG visualization of a GPX track
photo-geotag viz --input /path/to/track.gpx --out /path/to/map.png

# Render static map and interactive HTML from mapping proposal
photo-geotag viz --input /path/to/mapping.jsonl --out /path/to/map.png --html /path/to/map.html
```

### 4. `verify`

Reads EXIF metadata back from photo files to validate that GPS tags were correctly written and match expected coordinates within an acceptable tolerance.

```bash
# Verify photos against a GPX track
photo-geotag verify --photos /path/to/photos --gpx /path/to/track.gpx

# Verify photos against a mapping proposal
photo-geotag verify --photos /path/to/photos --mapping /path/to/mapping.jsonl
```

---

## Where the Apps Fit

1. **On the Outing**: Open the watch app on Apple Watch and tap **Start**. The app records coordinates in the background using an `HKWorkoutSession` that is discarded upon completion, leaving Apple Fitness and Health completely untouched.
2. **After the Outing**: Tap **Stop** on the watch. The track transfers automatically to the iPhone companion app via `WatchConnectivity`.
3. **Exporting**: Open the iPhone app, review the recorded route on the map view, and export the session as a standard `.gpx` file via AirDrop, Files, or email to your desktop computer.
4. **Processing**: Run `photo-geotag merge` against your staging directory of photos prior to importing them into your photo library.

---

## Verified on Device

The capture layer has been exercised on a physical Apple Watch (Apple Watch Ultra 4):

- **Background recording**: a 48-minute session recorded continuously with the app in the background and the screen off. Battery drain was about **2%** for the whole session.
- **Health isolation**: the session produced **no** workout, calorie, or exercise-ring entry in Apple Fitness or Health.
- **Recording continues in the background**: it stops only when you tap Stop, force-quit the app, or the system ends the session.
- **Known limitation**: while indoors with no GPS fix, no trackpoints are recorded, so a track can contain a gap for the time spent without a fix. Outdoors, points are logged about once per second.
