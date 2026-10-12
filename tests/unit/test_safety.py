"""Photo library safety guard."""

from __future__ import annotations

import pytest

from photo_geotag.errors import SafetyError
from photo_geotag.safety import assert_safe_path


def test_rejects_direct_library_path(tmp_path):
    target = tmp_path / "Photos.photoslibrary" / "originals" / "a.jpg"
    with pytest.raises(SafetyError):
        assert_safe_path(target)


def test_rejects_nested_library_path(tmp_path):
    target = tmp_path / "x" / "Library.photoslibrary" / "Masters" / "b.jpg"
    with pytest.raises(SafetyError):
        assert_safe_path(target)


def test_case_insensitive_suffix(tmp_path):
    target = tmp_path / "Photos.PHOTOSLIBRARY" / "c.jpg"
    with pytest.raises(SafetyError):
        assert_safe_path(target)


def test_allows_regular_directory(tmp_path):
    assert assert_safe_path(tmp_path) == tmp_path.resolve()
