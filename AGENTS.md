# AGENTS.md — Agent Guidelines for photo-geotag

This document specifies the operational rules, environment constraints, and safety boundaries for AI coding assistants working in the `photo-geotag` repository.

---

## 1. Project Structure

Keep repository artifacts organized under the following standard hierarchy:

```
photo-geotag/
├── src/
│   └── photo_geotag/         # Core Python package implementation
│       ├── __init__.py
│       ├── cli.py            # CLI parser and command dispatch
│       ├── merge.py          # GPX-to-EXIF matching logic
│       ├── fallback.py       # Anchor-table fallback generator
│       ├── viz.py            # Static map and HTML visualization
│       └── verify.py         # EXIF GPS assertion and audit routines
├── scripts/                  # Thin executable wrapper scripts
├── docs/                     # Documentation and architecture specs
│   ├── prd.md                # Product Requirements Document
│   ├── rfc.md                # Architecture and design decisions
│   ├── test.md               # Testing strategy and acceptance checklist
│   └── working.md            # Active task tracking and progress log
├── skills/                   # Agent skill specifications
│   └── photo_geotag.md       # Root skill entrypoint for autonomous tasks
├── tests/                    # Automated test suites
│   ├── unit/                 # Fast, dependency-isolated unit tests
│   ├── integration/          # Tests asserting exiftool interaction
│   └── fixtures/             # Synthetic test files and fake GPX tracks
├── pyproject.toml            # Python packaging and dependency declarations
└── README.md                 # User-facing project documentation
```

For native Apple platform components (watchOS and iOS companion targets), files reside in the corresponding Xcode workspace under `apps/` or the root project configuration.

---

## 2. Active Task Tracking (`docs/working.md`)

Agents must maintain execution state in `docs/working.md`:

- **Before execution**: Record the plan, current scope, and expected checkpoints.
- **During execution**: Check off finished steps, log intermediate findings, and document deviations or edge cases.
- **After execution**: Confirm acceptance criteria, summarize verification results, and list remaining actions.

Do not delete or overwrite historical logs unless explicitly directed; append status updates predictably.

---

## 3. Version Control Boundaries

Agents must observe strict version-control discipline:

- **Commit only when instructed**: Do not create Git commits autonomously. Only execute `git commit` when explicitly commanded by the user.
- **Small and reversible commits**: When authorized, create atomic, focused commits with clear, descriptive messages explaining what changed and why.
- **No indiscriminate staging**: Never run `git add -A` or `git add .`. Explicitly stage individual, task-relevant files.
- **Pre-commit privacy check**: Verify that staged files contain no credentials, private paths, or unintended binary artifacts before committing.

---

## 4. Language and Documentation Discipline

- **English only**: All source code, docstrings, inline comments, commit messages, documentation files, and agent skills must be written strictly in clear, idiomatic English.
- **No filler**: Keep technical documents focused, direct, and free of conversational padding or generic preambles.
- **Accurate nomenclature**: Always distinguish between capture layer components (watchOS/iOS) and merge layer components (CLI).

---

## 5. Synthetic Fixtures and Data Constraints

This repository targets a public open-source distribution. Strict privacy constraints apply:

- **Fake examples only**: All configuration files, CLI examples, and documentation snippets must use placeholder paths (e.g., `/path/to/photos`, `/path/to/output`), mock domains (e.g., `example.com`), and synthetic emails (e.g., `alice@example.com`).
- **No real coordinates or trips**: Use synthetic geographic coordinates (e.g., standard reference points) and synthetic dates. Never reference real personal trips, family names, private albums, or home locations.
- **No secrets or credentials**: Never commit API keys, token files, password references, or 1Password vault paths (`op://...`).
- **No machine-specific paths**: Avoid referencing absolute paths rooted in local user home directories (e.g., `/Users/username/...`).

---

## 6. Python and `uv` Environment Management

All Python tooling and tests must run within a virtual environment managed by `uv`:

- **Environment verification**: Verify whether a `.venv` directory exists in the project root. If absent, create one using `uv venv`.
- **Environment activation**: Always activate the virtual environment (`source .venv/bin/activate`) before running commands or executing tests.
- **Dependency installation**: Always use `uv pip install <package>` rather than `pip install`.
- **Reproducibility**: Ensure all package dependencies are properly declared in `pyproject.toml`.

---

## 7. Storage and Execution Boundaries

- **Strict pre-import boundary**: The CLI must operate solely on pre-import file copies stored in regular staging directories.
- **Never touch photo library bundles**: The CLI must never read, write, or scan files inside macOS photo libraries (such as `.photoslibrary` directory packages) or active database bundles. Modifying library internals directly risks metadata desynchronization and database corruption.
- **No health/fitness framing**: The capture tools use Apple Watch background session capabilities solely to obtain GPS location traces. Never introduce health metrics, workout calories, heart rates, or fitness-related concepts into code, documentation, or UI strings.
