# Interface Contract (frozen)

This file freezes the interfaces that the CLI and the apps depend on. Change it before
changing the code that implements it.

## 1. CLI

Binary: `photo-geotag` (installed entry point; package `src/photo_geotag/`).

### 1.1 `merge`

Write GPS EXIF into photos from a GPX track, matched by capture time.

```
photo-geotag merge --gpx TRACK.gpx --photos DIR
                   [--out DIR]            # write copies here; default: in place
                   [--tz-offset OFFSET]   # e.g. "+08:00", "-05:00"; default: +00:00
                   [--max-gap SECONDS]    # interpolation/extrapolation window; default 300
                   [--dry-run]
```

- `--tz-offset` is the timezone of the photo wall-clock (`DateTimeOriginal`). Each photo's
  local wall-clock time is converted to UTC with this offset before it is matched to the
  track. An implementation may delegate this to exiftool (`-Geotime<${DateTimeOriginal}OFFSET`)
  or compute it directly; the observable result must be identical and independent of the
  host machine timezone. Default `+00:00` (treat photo time as UTC).
- A photo whose capture time falls outside the track by more than `--max-gap` is reported as
  skipped, not silently stamped.

### 1.2 `fallback`

Build a per-photo location proposal from an anchor table when no track exists.

```
photo-geotag fallback --anchors ANCHORS.csv --photos DIR --out MAPPING.jsonl
                      [--viz MAP.png]
                      [--tz-offset OFFSET]
```

### 1.3 `viz`

Render a track or a proposal.

```
photo-geotag viz --input (TRACK.gpx | MAPPING.jsonl) --out MAP.png [--html MAP.html]
```

### 1.4 `verify`

Read EXIF back and assert.

```
photo-geotag verify --photos DIR (--gpx TRACK.gpx | --mapping MAPPING.jsonl)
                    [--tolerance-deg 0.0001] [--tz-offset OFFSET]
```

- `--tz-offset` (default `+00:00`) lets `verify --gpx` re-derive the expected coordinates the
  same way `merge` did, when the photos were shot in a non-UTC timezone.

### 1.5 Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 2 | Usage / argument error |
| 3 | Safety violation (a path resolves inside a `.photoslibrary` bundle) |
| 4 | Partial success (merge: some photos skipped, e.g. outside track window) |
| 5 | Verification mismatch |

`fallback` exits `0` even when some records are `contested`: a contested record is a valid
emitted result, not a partial failure. Exit `4` is reserved for `merge` skips.

### 1.6 Environment

| Variable | Purpose | Default |
|---|---|---|
| `PHOTO_GEOTAG_EXIFTOOL` | exiftool binary | `exiftool` |
| `PHOTO_GEOTAG_WORKDIR` | base for generated outputs | `./out` |

### 1.7 Hard boundary

Every subcommand must reject any input or output path that resolves inside a
`.photoslibrary` directory package, with exit code 3 and an explicit message, before any
file write.

## 2. Anchor table (CSV)

Header row required. Extra columns are ignored.

```csv
date,latitude,longitude,place_name
2026-05-10,37.7749,-122.4194,San Francisco
2026-05-11,36.6002,-121.8947,Monterey
```

- `date` is `YYYY-MM-DD`, interpreted in the local date of the photos.
- A date may appear once. If a date needs multiple locations, the record is contested (see
  2.1) rather than assigned.

### 2.1 Contest rule

When a photo's date has no anchor, or the anchor conflicts with other evidence, emit a
contested record (below) and do not assign coordinates.

## 3. Proposal file (`mapping.jsonl`)

One JSON object per line. UTF-8.

Proposed record:

```json
{"photo_path": "/path/to/photos/DSC_0102.JPG", "capture_time": "2026-05-10T14:32:00", "latitude": 37.7749, "longitude": -122.4194, "source": "anchor", "place_name": "San Francisco", "status": "proposed"}
```

Contested record:

```json
{"photo_path": "/path/to/photos/DSC_0199.JPG", "capture_time": "2026-05-10T23:45:00", "latitude": null, "longitude": null, "source": "anchor", "place_name": null, "status": "contested", "reason": "no anchor for date 2026-05-10"}
```

Fields:

| Field | Type | Notes |
|---|---|---|
| `photo_path` | string | absolute path of the pre-import copy |
| `capture_time` | string | local wall-clock `YYYY-MM-DDTHH:MM:SS`, no offset |
| `latitude` | number \| null | WGS84; null when contested |
| `longitude` | number \| null | WGS84; null when contested |
| `source` | string | `anchor` \| `track` |
| `place_name` | string \| null | from the anchor row |
| `status` | string | `proposed` \| `contested` |
| `reason` | string | present only when `status` is `contested` |

## 4. Track (GPX)

Standard GPX 1.1 with `<trk><trkseg><trkpt lat lon><time>`. Times are UTC ISO 8601.
Any conforming GPX from any device is valid input.

## 5. Capture apps (contract with the CLI)

- The watch app writes a GPX file per recording session.
- The iOS app stores sessions locally and can export a session as a `.gpx` file.
- The GPX file is the only interface between the apps and the CLI. The CLI never reads app
  storage or any photo library.

## 6. Verification report (`verify`, stdout JSON)

```json
{"total_photos": 42, "verified_photos": 42, "mismatches": 0, "missing_gps": 0, "tolerance_deg": 0.0001, "status": "passed"}
```
