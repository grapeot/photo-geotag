# RFC: photo-geotag Architecture and Technical Design

## 1. Abstract

This document outlines the architecture, component boundaries, and core design rationale for `photo-geotag`, a cross-platform toolkit designed to inject geographical coordinates into standalone camera photos.

The system is structured around a strict two-layer decoupling:
1. **A Capture Layer** implemented as native Apple companion targets (watchOS and iOS) that records GPS tracks without polluting health data.
2. **A Merge Layer** implemented as a standalone, device-agnostic Python CLI that merges GPX tracks or coarse daily anchor tables into photo EXIF metadata via `exiftool`.

---

## 2. High-Level Architecture

The primary structural decision of `photo-geotag` is the complete decoupling between track generation and metadata tagging.

```mermaid
graph TD
    subgraph Capture Layer [Capture Layer: Apple Ecosystem]
        W[watchOS Target] -->|HKWorkoutSession (discarded)| GPS[CoreLocation Engine]
        GPS -->|Incremental append| WS[Watch Local Storage]
        WS -->|WatchConnectivity| IP[iOS Companion Host]
        IP -->|UI Map View| MV[Map Visualization]
        IP -->|Share Sheet / AirDrop / Files| GPX[Standard GPX File]
    end

    subgraph Merge Layer [Merge Layer: Python CLI]
        GPX -->|Trackpoints| CLI[photo-geotag CLI]
        EXT_GPX[Third-Party GPX File] --> CLI
        ANC[Daily Anchor Table] --> CLI
        PHOTOS[Pre-Import Photo Copies] --> CLI
        
        CLI -->|merge| ET[exiftool engine]
        CLI -->|fallback| JL[mapping.jsonl]
        CLI -->|viz| MAP[Static PNG / HTML Map]
        CLI -->|verify| CHK[EXIF Assertion Audit]
        
        ET -->|Injected EXIF| TAGGED[Geotagged Photo Files]
    end

    classDef capture fill:#e1f5fe,stroke:#0288d1,stroke-width:2px;
    classDef merge fill:#e8f5e9,stroke:#388e3c,stroke-width:2px;
    class W,GPS,WS,IP,MV,GPX capture;
    class CLI,EXT_GPX,ANC,PHOTOS,ET,JL,MAP,CHK,TAGGED merge;
```

### Decoupling Rationale

1. **Device Agnosticism**: The merge layer treats all GPX files identically. Users may capture tracks using the Apple Watch companion app, third-party phone trackers, cycling computers, or dedicated GPS units.
2. **Resilience to Missing Tracks**: If track logging fails, the battery runs out, or the user forgets to record an outing, the merge layer transitions seamlessly to the fallback anchor pipeline without altering its downstream verification or visualization workflows.
3. **Independent Release Cycles**: The Python CLI can be maintained, tested, and distributed independently of Apple platform SDK updates and Xcode version requirements.

---

## 3. Component Specifications

### 3.1 Watch App (`watchOS`)

The watch app is an embedded target hosted within the iOS companion application.

- **Background Execution Contract**: watchOS aggressively throttles background execution and pauses location updates when the wrist is lowered. Apple allows sustained high-frequency location sampling only during active `HKWorkoutSession` runs.
- **The Discard Session Pattern**:
  - The app initializes an `HKWorkoutSession` with `HKWorkoutConfiguration` set to `.walking` or `.other`.
  - The session starts, granting continuous background runtime and enabling the paired `CLLocationManager` to stream location updates.
  - Locations are appended to an on-disk buffer file (`current_session.gpx.part`).
  - When the user taps **Stop**, the app ends the session with `healthStore.end(session)` and discards the associated live builder (`builder.discardWorkout()`), or simply never calls `builder.finishWorkout(...)`, so no `HKWorkout` is created.
  - **Critical Guarantee**: By ending the session without finalizing and saving a workout, zero workout records, zero heart rate readings, and zero calorie logs are registered in Apple Health or Fitness.
- **Data Persistence**: Track points are written incrementally as serialized XML snippets. If the watch runs out of battery mid-session, all points up to the last flush are preserved.
- **User Interface**: Minimalist single-button interface (Start/Stop). Automatically adheres to system light/dark mode and delivers localized strings in English and Chinese.

### 3.2 iPhone App (`iOS`)

The iOS app acts as the receiver and conduit for the watch app.

- **Transfer Protocol**: Uses `WCSession` (`WatchConnectivity` framework) using `transferFile(_:metadata:)` or `sendMessage(_:replyHandler:)` to ensure reliable background delivery even if the iPhone is locked when the session ends.
- **Session Management**: Parses the received file, stores it in the app's local sandbox, and renders an interactive `MapKit` trace of the route.
- **Export Pipeline**: Exposes standard iOS export interfaces:
  - `UIActivityViewController` (Share Sheet) for direct AirDrop to a Mac.
  - Direct export to the iOS Files app or cloud drives.
- **Appearance & Localization**: Full English and Chinese localization matching system preferences; responsive to light and dark system appearances.

### 3.3 CLI (`src/photo_geotag/`)

The CLI is structured into modular domain packages:

```
src/photo_geotag/
├── cli.py            # Entrypoint routing and argparse definitions
├── merge.py          # GPX time matching and exiftool orchestration
├── fallback.py       # Anchor-table date-to-location resolution
├── viz.py            # Map rendering using matplotlib / contextily / folium
└── verify.py         # EXIF read-back and coordinate assertion
```

#### Subcommand 1: `merge`
- **Matching Algorithm**:
  1. Parses the input GPX file into a sorted array of UTC timestamps and coordinate tuples `(lat, lon, ele)`.
  2. Scans the photo directory, extracting `DateTimeOriginal` from each image.
  3. Computes the target timestamp in UTC by applying the supplied `--tz-offset`.
  4. Linearly interpolates the exact coordinates between the nearest bounding GPX points if the delta is within the maximum time threshold (default: 300 seconds).
  5. Shells out to `exiftool` to write the GPS metadata into the files in-place or into a specified output directory.

#### Subcommand 2: `fallback`
- Used when no GPX track is available.
- Reads an anchor table containing: `date,latitude,longitude,place_name`.
- Maps each photo's capture date to the corresponding anchor record.
- Generates a `mapping.jsonl` proposal file:
  ```json
  {"photo_path": "/path/to/photos/IMG_1001.JPG", "date": "2026-05-10", "latitude": 37.7749, "longitude": -122.4194, "source": "anchor", "place": "San Francisco", "confidence": "coarse_daily"}
  ```
- Flags multi-location disputes or missing dates for manual review.

#### Subcommand 3: `viz`
- Consumes either a GPX file or a `mapping.jsonl` proposal.
- Generates a static geospatial preview (PNG) showing trackpoints or photo anchor clusters.
- Optionally emits a self-contained interactive HTML file for visual verification in any web browser.

#### Subcommand 4: `verify`
- Operates directly on processed photo files.
- Extracts `GPSLatitude`, `GPSLongitude`, `GPSLatitudeRef`, `GPSLongitudeRef`, and `GPSAltitude` via `exiftool`.
- Asserts that coordinates match expected target values within a specified geographic tolerance (default: ±0.0001°).

---

## 4. Key Design Decisions & Technical Trade-Offs

### 4.1 `HKWorkoutSession` with Discard vs. Pure CoreLocation Backgrounding

- **Alternative Considered**: Using `CLLocationManager` with `allowsBackgroundLocationUpdates = true` without HealthKit.
- **Why Rejected**: On watchOS, pure CoreLocation background tasks are terminated or throttled within minutes once the screen dims or another app becomes active. Apple strictly requires an active workout session to guarantee sustained background processing and GPS sampling.
- **Chosen Solution**: Employ `HKWorkoutSession` purely as a runtime scaffold, but never finalize/save a workout (discard the live builder) to preserve user privacy and prevent health metric corruption.

### 4.2 Shelling Out to `exiftool` vs. Native Python EXIF Libraries

- **Alternative Considered**: Embedding Python libraries such as `piexif` or `exif`.
- **Why Rejected**: Most pure Python EXIF packages only reliably support baseline JPEG files. They break or silently strip proprietary vendor MakerNotes on RAW formats (Canon CR2/CR3, Sony ARW, Nikon NEF, Fuji RAF, Adobe DNG).
- **Chosen Solution**: Delegate all physical metadata writes to `exiftool`. `exiftool` is universally recognized for safe, atomic, format-comprehensive metadata modification.

### 4.3 Handling Timezone Discrepancies

- **The Problem**: Digital cameras store local wall-clock time in `DateTimeOriginal` with no timezone offset (e.g., `2026-05-10 14:30:00`). GPX points are stored in UTC (e.g., `2026-05-10T06:30:00Z`). If processed on a computer set to PDT (UTC-7), `exiftool` by default assumes the local machine timezone, causing an 8-hour shift and tagging the wrong location.
- **Chosen Solution**: The `merge` subcommand explicitly accepts `--tz-offset` and formats the argument to `exiftool` using the `-Geotime<${DateTimeOriginal}${OFFSET}` construct, guaranteeing deterministic alignment regardless of the host machine's system clock.

### 4.4 Why the Capture Runs on Apple Watch, Not iPhone

- **Alternative Considered**: record the track with an iPhone app — a plain Core Location logger with the `location` background mode — and leave the watch out of scope.
- **Why Rejected (Reliability)**: On iOS, iPadOS, and watchOS the system suspends most apps shortly after they move to the background; while suspended an app does not run and does not receive live location updates, and the updates are delivered only when it runs again ([Apple: Handling location updates in the background](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background)). Continuous background location on iOS is therefore governed by OS lifecycle management rather than guaranteed. A user force-quit stops updates until the app is relaunched or a significant-location-change or region event brings it back ([pawanpoudel](https://pawanpoudel.svbtle.com/how-to-debug-significant-location-change-code-in-ios); [Apple Developer Forums](https://developer.apple.com/forums/thread/69152)), and developers repeatedly report background tracking "turning off after a while" ([Stack Overflow](https://stackoverflow.com/questions/80006914/ios-background-location-tracking-turns-off-after-sometime); [capawesome](https://capawesome.io/blog/why-ios-stops-sending-background-location-updates/); [bglocation.dev](https://bglocation.dev/blog/background-location-ios-app-killed)). For a recorder that is meant to be turned on and forgotten for the whole outing, that is the wrong failure mode.
- **Why Rejected (Battery)**: Continuous high-accuracy GPS is one of the most expensive things an iPhone can do. A naive, foreground-frequency logger can drain a phone in a few hours, and `kCLLocationAccuracyBest` consumes materially more than coarser settings ([Rangle](https://rangle.io/blog/optimizing-ios-location-services)). That cost lands on the device the user also depends on for navigation, payments, boarding passes, and messages — on the very day the recording matters most.
- **Chosen Solution**: Record on the Apple Watch using an `HKWorkoutSession`, Apple's sanctioned mechanism for sustained background runtime and sensor access (see 4.1). The watch has its own GNSS and its own battery and is worn on the wrist, so it is physically with the shooter. Measured: a 48-minute background recording on an Apple Watch Ultra 4 used about **2%** battery, with no iPhone-side logging.
- **Trade-offs Accepted**: The watch app must ship as a paired app embedded in the iOS target and needs its own provisioning profile (HealthKit), which makes the capture layer heavier to build and sign than a single iOS target.

> Note: a track can contain gaps for time spent indoors without a GPS fix. This is inherent to GPS on any device — an iPhone logger has the same gap — and is not a cost specific to recording on the watch.

### 4.5 One Workout Session at a Time, and Preemption

watchOS runs a single workout session at a time. If a second workout starts while the photo track is
recording — the system Workout app, or any third-party fitness app — WatchKit ends this app's
session and delivers `HKError.Code.errorAnotherWorkoutSessionStarted` to the session delegate, and
the session stops (Apple, [`HKWorkoutSession`](https://developer.apple.com/documentation/healthkit/hkworkoutsession)).
This is an OS-level constraint, not a defect in this app, and it cannot be worked around: two apps
cannot hold workout sessions simultaneously, and while the app is suspended after losing its
session it cannot restart itself.

Because the capture is a convenience (a GPS track), not a workout, the app does not compete for the
session. Instead:

- **Preemption is handled explicitly.** The recorder treats `errorAnotherWorkoutSessionStarted` and
  a transition to `.ended` as an abnormal stop: it finalizes the partial track, transfers it to the
  iPhone, returns to idle, and surfaces "Stopped: another workout started" rather than leaving a
  stale "Recording" state on screen.
- **Orphaned recordings are recovered.** If the app is terminated mid-session (preemption, crash, or
  power loss), the streamed `current_session.gpx.part` is left on disk. On the next launch the
  recorder rescues its points, writes a complete GPX, and transfers it, so a session that never
  stopped cleanly is not lost.

The corollary is a product decision, not a limitation: the watch recorder and a user's own workouts
are complementary sources. When the user is already running a workout, its route is recorded by
that app into Health, and the iOS app can read it back (see §3.2) rather than the two competing.

---

## 5. Boundaries and Non-Goals

1. **Never Touch Photo Library Bundles**:
   - `photo-geotag` strictly rejects paths resolving inside `.photoslibrary` directory packages. Direct writes to internal library bundles corrupt the underlying SQLite catalog and desynchronize system thumbnails. Geotagging must precede library import.
2. **No Health or Fitness Metrics**:
   - The project does not calculate heart rate, active calories, distance traveled, or split times.
3. **No Centralized Cloud Infrastructure**:
   - The toolkit operates 100% offline. There is no user authentication, telemetry, or remote server dependency.
