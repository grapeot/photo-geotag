# Test Strategy: photo-geotag

This document outlines the testing strategy, test layers, environment requirements, and manual verification criteria for `photo-geotag`.

---

## 1. Testing Philosophy

The test suite enforces three primary guarantees:
1. **Metadata Safety**: Geotagging operations must never corrupt original photo binaries or write to photo library packages.
2. **Deterministic Time & Spatial Alignment**: Timezone offsets, timestamp parsing, and coordinate interpolations must produce reproducible results regardless of host machine settings.
3. **Decoupled Verification**: Because physical Apple Watch execution cannot run headlessly in CI, the system boundary is verified at the GPX interface using synthetic fixtures.

---

## 2. Test Pyramid & Coverage

```
               / \
              /   \
             / HIL \         <- Human-in-the-Loop & Manual Acceptance
            /-------\
           /  Integ  \       <- Integration Tests (exiftool & synthetic files)
          /-----------\
         /    Unit     \     <- Fast Unit Tests (parsing, math, schema)
        /---------------\
```

### 2.1 Unit Tests (`tests/unit/`)

Unit tests execute entirely in Python without external binaries or network access.

- **CLI Parsing (`test_cli.py`)**:
  - Argument parsing and validation for `merge`, `fallback`, `viz`, and `verify`.
  - Rejection of invalid timezone strings, malformed coordinate pairs, or missing required flags.
- **GPX Parser & Interpolator (`test_gpx.py`)**:
  - Parsing standard GPX 1.1 tracks into structured points.
  - Handling tracks with non-uniform point intervals and single-point tracks.
  - Linear spherical interpolation between two trackpoints for a given timestamp.
  - Enforcement of maximum time tolerance thresholds (skipping photos taken outside track duration).
- **Timezone Calculations (`test_timezone.py`)**:
  - Converting local `DateTimeOriginal` wall-clock timestamps with explicit offsets (e.g., `+08:00`, `-05:00`) into UTC.
  - Formatting valid `-Geotime<${DateTimeOriginal}...` arguments for `exiftool`.
- **Fallback Anchor Resolution (`test_fallback.py`)**:
  - Reading CSV/TSV anchor tables (`date,latitude,longitude,place_name`).
  - Matching photo timestamps to date boundaries.
  - Serialization of `mapping.jsonl` entries.
  - Identification and flagging of ambiguous/contested dates (multiple anchor locations for one date).
- **Path & Security Guardrails (`test_safety.py`)**:
  - Immediate exception raising if any input or target path resides within a `.photoslibrary` bundle.

### 2.2 Integration Tests (`tests/integration/`)

Integration tests require `exiftool` installed on the system `$PATH`. All tests operate on temporary directories with synthetic fixtures.

- **Prerequisites**:
  - Python 3.11+ in `.venv`.
  - `exiftool` binary available (`exiftool -ver`).
  - Synthetic JPEG, TIFF, and DNG test files located in `tests/fixtures/photos/`.
- **GPX Merge Workflow (`test_merge_integration.py`)**:
  - Create a staging directory containing synthetic test images with known `DateTimeOriginal` values.
  - Supply a synthetic GPX track spanning the photo timestamps.
  - Invoke `photo-geotag merge`.
  - Read EXIF metadata back via `exiftool` and assert that `GPSLatitude`, `GPSLongitude`, and `GPSAltitude` are accurately written.
- **Timezone Offset Assertion (`test_tz_merge.py`)**:
  - Configure test photos taken at `15:00:00` local wall-clock time in UTC+8.
  - Supply a GPX track recorded in UTC where the corresponding position occurs at `07:00:00Z`.
  - Run `merge --tz-offset "+08:00"`.
  - Assert that the written coordinates match the `07:00:00Z` trackpoint, verifying that host machine timezone does not corrupt temporal alignment.
- **Fallback to Visualization Pipeline (`test_fallback_viz.py`)**:
  - Execute `photo-geotag fallback` with synthetic anchor table and photo fixtures.
  - Verify that `mapping.jsonl` contains valid JSON per line and matches expected photo paths.
  - Execute `photo-geotag viz --input mapping.jsonl --out map.png --html map.html`.
  - Assert that `map.png` is generated with non-zero file size and valid PNG headers.
  - Assert that `map.html` is generated and contains valid HTML structure.
- **Verification Subcommand (`test_verify_integration.py`)**:
  - Run `photo-geotag verify` against tagged synthetic photos and assert exit code 0.
  - Intentionally alter photo EXIF coordinates and assert that `verify` detects the discrepancy, returns a non-zero exit code, and reports the mismatch.

---

## 3. End-to-End (E2E) Test Scope

### Does an Automated E2E Test Exist?

**No automated full-system E2E test runs from watch sensor to desktop CLI.**

#### Engineering Rationale:
1. **Hardware & Sandbox Constraints**: The watch app relies on physical CoreLocation GPS hardware and watchOS runtime session lifecycles. Headless CI environments cannot simulate continuous GPS movement, watch display dimming, or physical Bluetooth/Wi-Fi `WatchConnectivity` file transfers with high fidelity.
2. **Decoupled System Contract**: The boundary between the Apple capture layer and the Python merge layer is strictly the **standard GPX 1.1 file format**. Because the merge layer does not know or care how the GPX was generated, validating the GPX-to-EXIF pipeline via integration tests completely proves system correctness.

Physical hardware validation is covered via the structured manual test protocol below.

---

## 4. Human-in-the-Loop & Manual Acceptance Review

Before tagged releases or major platform updates, a human reviewer must execute and inspect the following acceptance artifacts:

| Area | Manual Test Procedure | Acceptance Criterion |
|---|---|---|
| **HealthKit Isolation** | 1. Start a 15-minute recording session on Apple Watch.<br>2. Walk outdoors to capture GPS points.<br>3. Tap Stop to discard the session.<br>4. Open Apple Health and Apple Fitness on the paired iPhone. | **Zero workouts, zero active calories, and zero exercise ring minutes** are recorded for the session window. |
| **Incremental Storage** | 1. Start recording on the watch.<br>2. Force restart the watch (simulating sudden battery depletion).<br>3. Inspect internal app sandbox storage. | The unfinalized GPX chunk contains all trackpoints recorded prior to the restart. |
| **Watch & iOS Localization** | 1. Switch iPhone and Watch system language to Simplified Chinese (`zh-Hans`).<br>2. Open both applications.<br>3. Switch system appearance between Light and Dark mode. | All UI strings appear properly in Chinese without truncated text; UI elements maintain high-contrast legibility in both light and dark modes. |
| **WatchConnectivity Export** | 1. Complete a session on Apple Watch.<br>2. Open iPhone app and wait for transfer.<br>3. Tap the session and share via AirDrop to a Mac. | The `.gpx` file appears on the Mac, passes XML validation, and contains valid `<trkpt>` nodes. |
| **Visual Map Quality** | 1. Generate map visualization via `photo-geotag viz`.<br>2. Inspect `map.png` and `map.html` in an image viewer and browser. | Track is continuous without erratic GPS jumps or rendering artifacts; coordinates properly center on the bounding box. |
| **Pre-Import Safety** | 1. Attempt to pass a path containing `.photoslibrary` to `merge`. | CLI aborts immediately with an explicit safety error message before any file operations occur. |
