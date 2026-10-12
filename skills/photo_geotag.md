# photo_geotag Skill

Geotag standalone camera photos using recorded GPX tracks or fallback anchor tables prior to photo library import, with zero health data pollution and verified EXIF output.

---

## 1. Testable Acceptance Criteria

An agent task involving `photo-geotag` is considered complete only when all applicable criteria below are verified:

1. **Safety Enforcement**: Target photo files reside strictly in staging directories outside any photo library. No command targets or inspects paths containing `.photoslibrary`.
2. **Deterministic Timezone Matching (`merge`)**:
   - Every target photo within the GPX track's temporal bounds has valid GPS EXIF tags (`GPSLatitude`, `GPSLongitude`, `GPSLatitudeRef`, `GPSLongitudeRef`) written.
   - Photos taken in a different timezone than the host machine use an explicit `--tz-offset` parameter.
   - Command exits with return code `0`.
3. **Structured Proposal Generation (`fallback`)**:
   - When no GPX track exists, `mapping.jsonl` is emitted where each line conforms to the required JSON schema.
   - Ambiguous dates (e.g., dates with conflicting locations or multiple anchors) are explicitly marked with `status: "contested"` rather than silently assigned.
4. **Visual Artifact Production (`viz`)**:
   - Static map (`.png`) and/or interactive map (`.html`) files are created with valid headers, non-zero file sizes, and bounding boxes that encompass all track or anchor points.
5. **Read-Back Verification (`verify`)**:
   - `photo-geotag verify` reads back the EXIF metadata directly from the modified image files and asserts that coordinates match the expected GPX or mapping ground truth within ±0.0001°.
   - Verification output reports zero unmatched or corrupted files.

---

## 2. Resources & Hard Boundaries

### Available Resources
- **CLI Binary**: `photo-geotag` executable inside the active Python virtual environment (`.venv`).
- **External Dependency**: `exiftool` on system `$PATH`.
- **Source Code**: Python package under `src/photo_geotag/`, entrypoints under `scripts/`.
- **Companion Apps**: Xcode project for watchOS and iOS companion apps.

### Hard Boundaries (Non-Negotiable)
- **NEVER touch photo library bundles**: Do not read, write, or scan inside `.photoslibrary` directories. Geotagging must always occur on pre-import files in standard folders.
- **NEVER generate health or fitness records**: The watch app must only use `HKWorkoutSession` for background execution and sensor access, and must discard the session immediately upon completion.
- **NO real personal data or machine paths**: Always use fake paths (e.g., `/path/to/photos`), mock emails (e.g., `alice@example.com`), and synthetic coordinates in tests, logs, and documentation.
- **NO silent fallback assignments**: If camera clock timestamps dispute the anchor table or if multiple locations exist for one date, flag the record as contested.

---

## 3. Output Specifications

### 3.1 Fallback Proposal File (`mapping.jsonl`)
Each line in `mapping.jsonl` must be a valid JSON object matching this schema:

```json
{
  "photo_path": "/path/to/photos/DSC_0102.JPG",
  "capture_time": "2026-05-10T14:32:00",
  "latitude": 37.7749,
  "longitude": -122.4194,
  "source": "anchor",
  "place_name": "San Francisco",
  "status": "proposed"
}
```

When a record is contested (e.g., conflicting locations or unresolvable timezones):

```json
{
  "photo_path": "/path/to/photos/DSC_0199.JPG",
  "capture_time": "2026-05-10T23:45:00",
  "latitude": null,
  "longitude": null,
  "source": "anchor",
  "place_name": null,
  "status": "contested",
  "reason": "Multiple locations recorded for date 2026-05-10"
}
```

### 3.2 Verification Output (`verify`)
The `verify` command outputs a JSON summary report to stdout:

```json
{
  "total_photos": 42,
  "verified_photos": 42,
  "mismatches": 0,
  "missing_gps": 0,
  "tolerance_deg": 0.0001,
  "status": "passed"
}
```

---

## 4. Known Pitfalls & Countermeasures

1. **Timezone Discrepancies**:
   - *Pitfall*: `DateTimeOriginal` in photo EXIF is wall-clock local time with no timezone indicator. `exiftool` interprets it in the host machine's local timezone by default. If the photos were captured in a different timezone than the computer executing `merge`, naive matching applies the wrong time and mislocates the photos.
   - *Countermeasure*: Always verify the shooting timezone and pass the explicit offset (e.g., `--tz-offset "+08:00"`). In the underlying call, format as `-Geotime<${DateTimeOriginal}+08:00`.
2. **Order of Operations**:
   - *Pitfall*: Attempting to geotag photos after importing them into a photo library (such as Apple Photos) fails because photo management apps only read and index EXIF coordinates during initial ingestion.
   - *Countermeasure*: Complete all geotagging and verification on pre-import copies before initiating import into any photo library.
3. **Reference Device Photo Location vs. Shooting Location**:
   - *Pitfall*: Using a smartphone photo's coordinates as a proxy for a dedicated camera photo can introduce significant errors (e.g., phone photo taken earlier from a scenic lookout vs. camera photo taken later down in a valley).
   - *Countermeasure*: Never treat another device's photo as an absolute coordinate reference without verifying timestamps and proximity. Prefer continuous GPX tracks.
4. **Coarseness of Daily Anchors**:
   - *Pitfall*: Assigning a single anchor per day (`date -> place`) incorrectly lumps morning, afternoon, and evening activities in different cities or neighborhoods into a single coordinate point.
   - *Countermeasure*: Treat fallback mapping as a coarse initial proposal. Always inspect `viz` output and flag multi-activity travel days.
5. **Geocoding Ambiguity**:
   - *Pitfall*: Place-name lookups frequently return same-named towns or landmarks in different countries or states (e.g., "Paris, Texas" vs. "Paris, France").
   - *Countermeasure*: Always inspect and verify latitude/longitude values in the anchor table before running `fallback`. Never rely on unverified string-based geocoding.
6. **Clock & Timezone Disputes**:
   - *Pitfall*: Standalone camera internal clocks frequently drift or were never adjusted when crossing timezones, causing photos to disagree with both the track and the itinerary.
   - *Countermeasure*: Flag contested records with `status: "contested"` instead of forcing silent assignment. Check a reference timestamp before bulk processing.

---

## 5. Result-Oriented Execution Guidance

When an agent is tasked with running geotagging workflows:

- **Orient on Evidence First**: Inspect the photo directory and input tracks before running destructive operations. Verify that `exiftool` is installed, check file extensions, and sample one photo's `DateTimeOriginal` to confirm clock alignment.
- **Choose the Right Tool for the Situation**:
  - If a valid GPX track covers the photo timestamps -> use `merge`.
  - If no track exists but an anchor table is available -> use `fallback` to emit `mapping.jsonl`, run `viz` to inspect the proposal, and then apply.
  - If track coverage is partial -> run `merge` for covered timestamps and `fallback` for the remainder, explicitly flagging boundaries.
- **Always Close the Verification Loop**: Never assume `exiftool` succeeded simply because it returned code 0. Always run `verify` to confirm that the EXIF tags exist on disk and match expected coordinates within tolerance.
