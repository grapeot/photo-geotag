"""Exit codes and exceptions shared across the CLI.

See docs/interface.md section 1.5 for the contract.
"""

from __future__ import annotations

EXIT_OK = 0
EXIT_USAGE = 2
EXIT_SAFETY = 3
EXIT_PARTIAL = 4
EXIT_VERIFY = 5


class PhotoGeotagError(Exception):
    """Base error carrying a process exit code."""

    exit_code = EXIT_USAGE


class UsageError(PhotoGeotagError):
    exit_code = EXIT_USAGE


class SafetyError(PhotoGeotagError):
    exit_code = EXIT_SAFETY


class PartialError(PhotoGeotagError):
    exit_code = EXIT_PARTIAL


class VerifyError(PhotoGeotagError):
    exit_code = EXIT_VERIFY


class ExiftoolNotFoundError(PhotoGeotagError):
    exit_code = EXIT_USAGE
