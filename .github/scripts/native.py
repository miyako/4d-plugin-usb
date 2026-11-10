"""Rebuild only proven macOS outputs; retain the selected prebuilt Windows payload."""

import argparse
from pathlib import Path
import re
import shutil

import repository

PRODUCT = "LIBUSB"
BASE = Path("LIBUSB.4dbase/Plugins")
BUNDLE = BASE / (PRODUCT + ".bundle")
WINDOWS = BUNDLE / "Contents/Windows64/LIBUSB.4DX"
FILES = tuple(BUNDLE / relative for relative in (
    "Contents/MacOS/LIBUSB", "Contents/Info.plist",
    "Contents/Resources/English.lproj/InfoPlist.strings",
    "Contents/Resources/constants.xlf", "Contents/Resources/manifest.json",
    "Contents/_CodeSignature/CodeResources",
))
XCODE_DATA = Path("build/XCBuildData")
DIRECTORIES = (
    Path("build/LIBUSB.build"),
    Path("build/Default/LIBUSB.build"),
    BASE / "LIBUSB.build",
    BASE / "Default/LIBUSB.build",
)


def generated(path):
    return (path in set(map(str, FILES))
            or re.fullmatch(r"build/XCBuildData/(?:build\.db(?:-wal|-shm)?|"
                            r"[0-9a-f]{32}\.xcbuilddata/.+)", path) is not None
            or any(path.startswith(str(directory) + "/") for directory in DIRECTORIES))


def validate_paths(paths):
    root = Path.cwd().resolve()
    for path in paths:
        for parent in (path, *path.parents):
            if parent == Path("."):
                break
            if repository.is_link(parent):
                raise ValueError(f"Refusing symlink output: {parent}")
        if not path.resolve().is_relative_to(root):
            raise ValueError(f"Output escapes checkout: {path}")
        if path.is_dir():
            for descendant in path.rglob("*"):
                if repository.is_link(descendant):
                    raise ValueError(f"Refusing symlink output: {descendant}")


def prepare():
    validate_paths((*FILES, *DIRECTORIES, XCODE_DATA))
    for path in FILES:
        if path.exists() and not path.is_file():
            raise ValueError(f"Expected regular cleanup leaf: {path}")
    for path in DIRECTORIES:
        if path.exists() and not path.is_dir():
            raise ValueError(f"Expected cleanup directory: {path}")
    for path in FILES:
        path.unlink(missing_ok=True)
    for path in DIRECTORIES:
        if path.exists():
            shutil.rmtree(path)


def require_file(path):
    validate_paths((path,))
    if not path.is_file() or path.stat().st_size == 0:
        raise ValueError(f"Missing or empty native output: {path}")


def verify_resources():
    for name in ("manifest.json", "constants.xlf"):
        copied = BUNDLE / "Contents/Resources" / name
        require_file(copied)
        if copied.read_bytes() != Path(name).read_bytes():
            raise ValueError(f"Copied resource differs from source: {copied}")


def verify_windows():
    require_file(WINDOWS)
    selected = repository.entries(repository.run(
        "git", "ls-tree", "-z", "HEAD", "--", str(WINDOWS)))
    if str(WINDOWS) not in selected or not repository.worktree_matches(
            repository.actual_blob(WINDOWS), selected[str(WINDOWS)]):
        raise ValueError("Prebuilt Windows payload differs from selected source")


def validate_outputs(*, signed=True):
    validate_paths((*FILES, WINDOWS, *DIRECTORIES, XCODE_DATA))
    for path in FILES:
        if signed or path != BUNDLE / "Contents/_CodeSignature/CodeResources":
            require_file(path)
    require_file(WINDOWS)
    for path in BUNDLE.rglob("*"):
        if not path.is_dir():
            require_file(path)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=("clean-macos", "verify-resources", "verify-unsigned"))
    phase = parser.parse_args().phase
    if phase == "clean-macos":
        prepare()
    elif phase == "verify-unsigned":
        validate_outputs(signed=False)
        verify_resources()
        verify_windows()
    else:
        verify_resources()
