"""The final publication exemption is smaller than the bundle or build roots."""

import unittest

from helper_support import source
import native


class GeneratedOutputTests(unittest.TestCase):
    def test_exact_native_files_and_controlled_directory_descendants(self):
        expected = (
            *map(str, native.FILES),
            "build/XCBuildData/build.db",
            "build/XCBuildData/build.db-wal",
            "build/XCBuildData/build.db-shm",
            "build/XCBuildData/0123456789abcdef0123456789abcdef.xcbuilddata/build-request.json",
            "build/LIBUSB.build/Objects-normal/arm64/main.o",
            "build/Default/LIBUSB.build/build.db",
            "LIBUSB.4dbase/Plugins/LIBUSB.build/Objects/file.o",
            "LIBUSB.4dbase/Plugins/Default/LIBUSB.build/Objects/file.o",
        )
        for path in expected:
            with self.subTest(path=path):
                self.assertTrue(native.generated(path))

    def test_every_resource_source_or_unproven_output_stays_protected(self):
        excluded = (
            str(native.WINDOWS),
            "LIBUSB.4dbase/Plugins/LIBUSB.bundle/Contents/MacOS/runtime.dylib",
            "LIBUSB.4dbase/Plugins/LIBUSB.bundle/Contents/QuickLook/Thumbnail.png",
            "LIBUSB.4dbase/Plugins/Default/LIBUSB.bundle/Contents/Info.plist",
            "LIBUSB.4dbase/Plugins/Default/keep", "build/XCBuildData-evil/build.db",
            "build/unexpected-source.cpp",
            "build/XCBuildData/unexpected-source.cpp",
            "build/XCBuildData/build.db-evil",
            "build/XCBuildData/evil.xcbuilddata/build-request.json",
            "build/LIBUSB.build-evil/injected.cpp",
            "LIBUSB.4dbase/Plugins/LIBUSB.bundle/Contents/_CodeSignature-evil/file",
            "LIBUSB.4dbase/Plugins/LIBUSB.bundle/Contents/Info.plist.backup",
            *map(str, source.SOURCE_PATHS),
        )
        for path in excluded:
            with self.subTest(path=path):
                self.assertFalse(native.generated(path))
