"""Safety guard: never operate inside a photo library bundle."""

from __future__ import annotations

from pathlib import Path

from .errors import SafetyError

LIBRARY_SUFFIX = ".photoslibrary"


def assert_safe_path(path: str | Path) -> Path:
    """Return the resolved path, or raise SafetyError if it is inside a library bundle."""
    p = Path(path).expanduser()
    try:
        resolved = p.resolve()
    except OSError:
        resolved = p.absolute()
    for part in resolved.parts:
        if part.lower().endswith(LIBRARY_SUFFIX):
            raise SafetyError(
                f"refusing to operate inside a photo library bundle: {resolved}"
            )
    return resolved
