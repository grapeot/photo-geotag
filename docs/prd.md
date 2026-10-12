# Product Requirements Document (PRD)

## 1. Problem Statement

Dedicated digital cameras (DSLRs, mirrorless bodies, compacts, and vintage digital units) produce high-quality photographs but frequently lack built-in GPS hardware or have power-hungry GPS receivers that photographers keep disabled. As a result, photos exported from memory cards lack geographic coordinates in their EXIF metadata.

When these photos are imported into photo management software, they cannot be searched by location, grouped by geographic clusters, or viewed on a map.

Existing solutions suffer from significant shortcomings:

1. **Fitness Tracking Pollution**: Users often rely on running or cycling workout apps on their smartwatches to record GPS breadcrumbs. However, saving these sessions clutters Apple Health and Fitness activity rings, workout histories, and calorie statistics with fake workouts that were actually casual photo outings.
2. **Library Ingestion Timing**: Most photo management applications (such as Apple Photos) only parse and index EXIF coordinates during initial ingestion. Attempting to geotag photos after import requires complex database surgery that risks library corruption.
3. **No Fallback for Missing Tracks**: When a photographer forgets to record a track, existing tools fail completely. There is no lightweight mechanism to apply coarse daily location anchors to uncoordinated shoots before ingestion.

`photo-geotag` solves these problems by providing an unobtrusive watch-based track recorder that leaves health statistics untouched, alongside an offline CLI that injects precise GPX tracks or coarse daily fallback anchors into pre-import photos.

---

## 2. Target Users

- **Enthusiast & Professional Photographers**: Users shooting with standalone cameras who carry an Apple Watch and iPhone and desire accurate coordinates on their photos without carrying dedicated handheld GPS loggers.
- **Privacy-Conscious Archivists**: Users who require local, offline-first processing without uploading personal photos or location histories to third-party cloud services.
- **Apple Watch Owners Who Value Health Data Integrity**: Individuals who want background GPS track recording without distorting their fitness rings, workout counts, or cardiovascular metrics in Apple Health.

---

## 3. Product Scope & Requirements

### 3.1 Component Architecture

The project consists of four decoupled components:
- **Watch App** (`watchOS`)
- **iPhone App** (`iOS`)
- **CLI** (`photo-geotag`)
- **Agent Skill** (`skills/photo_geotag.md`)

```
+-------------------------------------------------------------+
|                        Capture Layer                        |
|                                                             |
|   +-------------------+              +------------------+   |
|   |   Apple Watch     |   Watch      |    iPhone App    |   |
|   |  - HKWorkout      | Connectivity |  - Session Map   |   |
|   |    (discarded)    |------------->|  - Local Store   |   |
|   |  - Incremental GPX|              |  - GPX Export    |   |
|   +-------------------+              +------------------+   |
+------------------------------------------------|------------+
                                                 | (GPX File)
+------------------------------------------------v------------+
|                         Merge Layer                         |
|                                                             |
|   +-----------------------------------------------------+   |
|   |                 photo-geotag CLI                    |   |
|   |                                                     |   |
|   |  merge    : GPX + photos -> EXIF (via exiftool)     |   |
|   |  fallback : anchor table + photos -> mapping.jsonl  |   |
|   |  viz      : GPX or mapping.jsonl -> Map PNG / HTML  |   |
|   |  verify   : photos -> assert expected GPS tags      |   |
|   +-----------------------------------------------------+   |
|                              |                              |
|                              v                              |
|                   [ Pre-Import Photos ]                     |
+-------------------------------------------------------------+
```

### 3.2 Functional Requirements

#### 3.2.1 Watch App (`watchOS`)

- **FR-W1 (Background Logging)**: Must maintain continuous background location logging during an active recording session, even when the watch display sleeps.
- **FR-W2 (Health Isolation)**: Must utilize an `HKWorkoutSession` strictly to obtain background runtime execution and CoreLocation sensor privileges. It must **never** call `HKHealthStore.save()` and must explicitly discard the session upon termination, guaranteeing zero entries in Apple Fitness and Health.
- **FR-W3 (Crash Resilience)**: Must write GPS trackpoints incrementally to local watch storage so that unexpected termination does not corrupt or erase prior recorded points.
- **FR-W4 (Minimal Control)**: Provide a single toggle control (Start / Stop).
- **FR-W5 (Localization & Appearance)**: UI strings must support English and Chinese, automatically adopting system language settings. The visual interface must seamlessly adapt to system light and dark appearances.

#### 3.2.2 iPhone App (`iOS`)

- **FR-I1 (Companion Receiver)**: Shipped in the same Xcode project as the watch app. Must receive finished track sessions transferred from the watch via `WatchConnectivity`.
- **FR-I2 (Local Session Storage)**: Persist received track sessions locally on the device with date and duration metadata.
- **FR-I3 (Map Preview)**: Render the recorded track path on an interactive map view.
- **FR-I4 (GPX Export)**: Enable exporting recorded tracks as standard `.gpx` files through the iOS share sheet, AirDrop, or the Files application.
- **FR-I5 (Localization & Appearance)**: Bilingual support (English and Chinese) and light/dark appearance matching system settings.

#### 3.2.3 CLI (`photo-geotag`)

The CLI is packaged under `src/photo_geotag/` with entrypoints in `scripts/`. It supports four distinct subcommands:

- **FR-C1 (`merge`)**:
  - Accepts a GPX track file and a directory of pre-import photos.
  - Matches each photo's EXIF `DateTimeOriginal` to the interpolated GPX trackpoint.
  - Delegates writing of standard GPS EXIF tags (`GPSLatitude`, `GPSLongitude`, `GPSAltitude`, `GPSLatitudeRef`, `GPSLongitudeRef`) to `exiftool`.
  - Supports an explicit timezone offset parameter (e.g., `--tz-offset "+08:00"`) to resolve local camera clock ambiguity against UTC trackpoint timestamps.
- **FR-C2 (`fallback`)**:
  - Operates when no GPX track was captured.
  - Consumes an anchor table (date-to-place mappings) and a photo directory.
  - Emits a per-photo proposal file (`mapping.jsonl`) assigning coordinates based on the capture date.
  - Optionally generates a preview map visualization.
- **FR-C3 (`viz`)**:
  - Renders a geographic visualization of a GPX track or a `mapping.jsonl` proposal file.
  - Emits a static map image (PNG) and optionally an interactive HTML view.
- **FR-C4 (`verify`)**:
  - Reads EXIF tags directly back from specified photos.
  - Asserts that coordinates match expected positions (from a reference GPX track or `mapping.jsonl` proposal) within an allowable geographical threshold.

#### 3.2.4 Agent Skill (`skills/photo_geotag.md`)

- **FR-S1 (Agent Integration)**: Provides a machine-readable entry point specifying inputs, execution patterns, boundaries, and validation criteria for autonomous agents.

---

## 4. Boundaries and Safety Constraints

- **Pre-Import Only**: The CLI must operate exclusively on photo copies in regular file directories prior to importing them into any photo cataloging software.
- **No Direct Library Writes**: The CLI must **never** read, write, or alter files inside `.photoslibrary` bundles.
- **No Fitness Association**: No health metrics (e.g., calories, heart rate, step count) may be collected, stored, or referenced anywhere across the codebase or user interface.
- **Local & Offline**: All processing must function entirely without internet connectivity.

---

## 5. Measurable Success Criteria

| ID | Metric | Target | Verification Method |
|---|---|---|---|
| **SC-01** | Apple Health / Fitness workout entries created | Exactly **0** entries across all test runs | Audit Health and Fitness apps after 50 continuous recording cycles. |
| **SC-02** | Track transmission reliability | **100%** successful receipt on iPhone | Compare point counts between watch local cache and iPhone received GPX. |
| **SC-03** | EXIF coordinate accuracy | Matched within **±1 second** interpolation tolerance | Verify written EXIF tags against synthetic GPX ground truth. |
| **SC-04** | Timezone offset handling | **0%** timestamp drift when timezone offset is supplied | Run test photos across UTC-8, UTC+0, and UTC+8 against known UTC GPX timestamps. |
| **SC-05** | Library safety | Exactly **0** writes to `.photoslibrary` | Automated test asserting execution rejection on paths containing `.photoslibrary`. |
| **SC-06** | UI Internationalization | **100%** string coverage in English and Chinese | Xcode localized string audit across watchOS and iOS targets. |
