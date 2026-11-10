"""Narrow macOS cleanup, prebuilt Windows preservation and final output retention."""

import shutil
import stat
from types import SimpleNamespace
from unittest import mock

from helper_support import Fixture, GitFixture, cwd
import native
import repository


class NativePreparationTests(Fixture):
    def test_all_cleanup_targets_prevalidated_before_any_deletion(self):
        first = self.write(native.FILES[0], b"must remain")
        for relative in (native.FILES[-1], native.DIRECTORIES[-1]):
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            if relative in native.FILES:
                target.mkdir()
            else:
                target.write_bytes(b"not a directory")
            with cwd(self.root), self.assertRaisesRegex(ValueError, "cleanup"):
                native.prepare()
            self.assertEqual(first.read_bytes(), b"must remain")
            if target.is_dir():
                target.rmdir()
            else:
                target.unlink()

    def test_reparse_ancestor_rejected_before_first_deletion(self):
        first = self.write(native.FILES[0], b"must remain")
        self.write(native.DIRECTORIES[-1] / "object.o", b"must remain")
        real = type(first).lstat

        def reparse(path, *args, **kwargs):
            status = real(path, *args, **kwargs)
            if path == native.DIRECTORIES[-1]:
                return SimpleNamespace(st_mode=stat.S_IFDIR, st_file_attributes=0x400)
            return status

        with cwd(self.root), mock.patch("pathlib.Path.lstat", new=reparse):
            with self.assertRaisesRegex(ValueError, "symlink"):
                native.prepare()
        self.assertEqual(first.read_bytes(), b"must remain")
        self.assertEqual((self.root / native.DIRECTORIES[-1] / "object.o").read_bytes(), b"must remain")

    def test_xcode_database_directory_never_recursively_deleted(self):
        paths = (
            "build/XCBuildData/build.db",
            "build/XCBuildData/unexpected-source.cpp",
            "build/XCBuildData/evil.xcbuilddata/keep",
        )
        for relative in paths:
            self.write(relative, b"preserve original bytes")
        with cwd(self.root):
            native.prepare()
        for relative in paths:
            self.assertEqual((self.root / relative).read_bytes(), b"preserve original bytes")

    def test_unsigned_gate_does_not_require_future_signature_but_final_gate_does(self):
        for relative in native.FILES[:-1]:
            self.write(relative, b"fresh native leaf")
        self.write(native.WINDOWS, b"prebuilt Windows")
        with cwd(self.root):
            native.validate_outputs(signed=False)
            with self.assertRaisesRegex(ValueError, "Missing or empty"):
                native.validate_outputs()
        self.write(native.FILES[-1], b"fresh signature")
        with cwd(self.root):
            native.validate_outputs()

    def test_selective_cleanup_preserves_resources_dependencies_and_default_siblings(self):
        protected = (
            native.BUNDLE / "Contents/QuickLook/Thumbnail.png",
            native.BUNDLE / "Contents/MacOS/runtime.dylib",
            native.BUNDLE / "Contents/Resources/custom.txt",
            native.BASE / "Default/LIBUSB.bundle/Contents/Info.plist",
            native.BASE / "Default/keep", native.BASE / "Other.bundle/keep",
            "build/unrelated/keep", "a/libusb-1.0.a", "dylib/libusb-1.0.0.dylib",
            native.WINDOWS, native.BUNDLE / "Contents/CodeResources",
        )
        for path in protected:
            self.write(path, b"preserved")
        for path in native.FILES:
            self.write(path, b"stale")
        for path in native.DIRECTORIES:
            self.write(path / "intermediate", b"stale")
        with cwd(self.root):
            native.prepare()
            native.prepare()
        for path in protected:
            self.assertEqual((self.root / path).read_bytes(), b"preserved")
        for path in (*native.FILES, *native.DIRECTORIES):
            self.assertFalse((self.root / path).exists(), path)

    def test_symlink_anywhere_prevalidated_before_first_deletion(self):
        for where in (native.FILES[-1], native.DIRECTORIES[-1], native.BUNDLE,
                      native.DIRECTORIES[0] / "nested/link"):
            with self.subTest(where=where):
                first = self.write(native.FILES[0], b"must remain")
                destination = self.write("outside/keep", b"untouched")
                link = self.root / where
                if link.is_dir():
                    shutil.rmtree(link)
                link.parent.mkdir(parents=True, exist_ok=True)
                link.symlink_to(destination)
                with cwd(self.root), self.assertRaisesRegex(ValueError, "symlink"):
                    native.prepare()
                if where != native.BUNDLE:
                    self.assertEqual(first.read_bytes(), b"must remain")
                self.assertEqual(destination.read_bytes(), b"untouched")
                link.unlink()

    def test_cleanup_io_error_is_fatal(self):
        self.write(native.FILES[0], b"stale")
        with cwd(self.root), mock.patch("pathlib.Path.unlink", side_effect=PermissionError("denied")):
            with self.assertRaises(PermissionError):
                native.prepare()
        self.write(native.DIRECTORIES[0] / "stale", b"stale")
        with cwd(self.root), mock.patch("shutil.rmtree", side_effect=PermissionError("denied")):
            with self.assertRaises(PermissionError):
                native.prepare()

    def test_resources_must_be_fresh_exact_source_copies(self):
        for name in ("constants.xlf", "manifest.json"):
            self.write(name, b"source")
            self.write(native.BUNDLE / "Contents/Resources" / name, b"source")
        with cwd(self.root):
            native.verify_resources()
            (native.BUNDLE / "Contents/Resources/constants.xlf").write_bytes(b"stale")
            with self.assertRaisesRegex(ValueError, "differs"):
                native.verify_resources()


class GeneratedRetentionTests(GitFixture):
    def test_actual_xcode_database_wal_and_outputs_are_final_only(self):
        for relative in (
            *native.FILES,
            "build/XCBuildData/build.db", "build/XCBuildData/build.db-wal",
            "build/XCBuildData/build.db-shm",
            "build/XCBuildData/0123456789abcdef0123456789abcdef.xcbuilddata/build-request.json",
            "build/LIBUSB.build/Default/LIBUSB.build/Objects-normal/arm64/main.o",
            "build/Default/LIBUSB.build/main.o",
        ):
            target = self.local / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(b"fresh native output")
        with cwd(self.local):
            with self.assertRaises(ValueError):
                repository.verify_checkout(self.sha, generated=native.generated)
            repository.verify_checkout(self.sha, generated=native.generated, final=True)

    def test_evil_siblings_and_protected_resource_never_gain_final_exemption(self):
        for relative in (
            "build/XCBuildData-evil/build.db",
            "build/LIBUSB.build-evil/main.o",
            "build/unexpected-source.cpp",
            "Objs/Release-evil/main.obj",
            "Objs/Debug/main.obj",
            "winbuild/nested/LIBUSB.4DX",
            "LIBUSB.4dbase/Plugins/Default/LIBUSB.bundle/Contents/Info.plist",
            str(native.BUNDLE / "Contents/QuickLook/Thumbnail.png"),
            str(native.BUNDLE / "Contents/MacOS/runtime.dylib"),
            str(native.BUNDLE / "Contents/Resources/custom.txt"),
            str(native.BUNDLE / "Contents/_CodeSignature/evil"),
        ):
            with self.subTest(relative=relative):
                target = self.local / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(b"unexpected")
                with cwd(self.local), self.assertRaises(ValueError):
                    repository.verify_checkout(self.sha, generated=native.generated, final=True)
                target.unlink()
