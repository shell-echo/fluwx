import hashlib
from pathlib import Path
import plistlib
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import import_wechat_sdk as sdk


ARTIFACT = sdk.DEFAULT_OUTPUT


def hashes(root):
    return {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in root.rglob("*") if p.is_file()}


class WechatSdkPackagingTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.source, self.output = root / "vendor", root / "packaged"
        self.source.mkdir()
        # Restore the official framework layout around the unmodified committed
        # vendor archive bytes. Tests need no network or app credentials.
        info = plistlib.loads((ARTIFACT / "WechatOpenSDK.xcframework/Info.plist").read_bytes())
        for item in info["AvailableLibraries"]:
            original = ARTIFACT / "WechatOpenSDK.xcframework" / item["LibraryIdentifier"]
            target = self.source / item["LibraryIdentifier"] / "WechatOpenSDK.framework"
            target.mkdir(parents=True)
            shutil.copy2(original / "libWechatOpenSDK.a", target / "WechatOpenSDK")
            shutil.copytree(original / "Headers/WechatOpenSDK", target / "Headers")
            (target / "Modules").mkdir()
            (target / "Modules/module.modulemap").write_text("framework module WechatOpenSDK {}\n")
            (target / "Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": "WechatOpenSDK"}))
            item.update(LibraryPath="WechatOpenSDK.framework", BinaryPath="WechatOpenSDK.framework/WechatOpenSDK")
            item.pop("HeadersPath")
        (self.source / "Info.plist").write_bytes(plistlib.dumps(info))
        shutil.copy2(ARTIFACT / "Privacy/PrivacyInfo.xcprivacy", self.source / "PrivacyInfo.xcprivacy")
        self.output.mkdir()
        (self.output / "previous.txt").write_bytes(b"prior SDK")

    def test_code_headers_and_vendor_privacy_are_preserved(self):
        sdk.import_sdk(self.source, self.output, "2.0.8")
        info = plistlib.loads((self.output / "WechatOpenSDK.xcframework/Info.plist").read_bytes())
        for item in info["AvailableLibraries"]:
            self.assertEqual(item["LibraryPath"], "libWechatOpenSDK.a")
            self.assertEqual(item["HeadersPath"], "Headers")
            original = self.source / item["LibraryIdentifier"] / "WechatOpenSDK.framework"
            target = self.output / "WechatOpenSDK.xcframework" / item["LibraryIdentifier"]
            self.assertEqual((target / "libWechatOpenSDK.a").read_bytes(), (original / "WechatOpenSDK").read_bytes())
            self.assertEqual(hashes(target / "Headers/WechatOpenSDK"), hashes(original / "Headers"))
        self.assertFalse(list(self.output.rglob("*.framework")))
        self.assertFalse(list(self.output.rglob("*.dSYM")))
        self.assertEqual((self.output / "Privacy/PrivacyInfo.xcprivacy").read_bytes(), (self.source / "PrivacyInfo.xcprivacy").read_bytes())
        first = hashes(self.output)
        sdk.import_sdk(self.source, self.output, "2.0.8")
        self.assertEqual(first, hashes(self.output))

    def test_missing_privacy_preserves_previous_sdk(self):
        (self.source / "PrivacyInfo.xcprivacy").unlink()
        before = hashes(self.output)
        with self.assertRaises(FileNotFoundError):
            sdk.import_sdk(self.source, self.output, "2.0.8")
        self.assertEqual(hashes(self.output), before)

    def test_unreviewed_resource_does_not_silently_disappear(self):
        (self.source / "ios-arm64/WechatOpenSDK.framework/new-icon.png").write_bytes(b"icon")
        before = hashes(self.output)
        with self.assertRaisesRegex(ValueError, "unreviewed SDK resource"):
            sdk.import_sdk(self.source, self.output, "2.0.8")
        self.assertEqual(hashes(self.output), before)

    def test_non_archive_mach_o_is_rejected_before_replacement(self):
        # Use the active Python executable as a real non-archive Mach-O input.
        shutil.copy2(Path(sys.executable).resolve(), self.source / "ios-arm64/WechatOpenSDK.framework/WechatOpenSDK")
        before = hashes(self.output)
        with self.assertRaises((ValueError, sdk.subprocess.CalledProcessError)):
            sdk.import_sdk(self.source, self.output, "2.0.8")
        self.assertEqual(hashes(self.output), before)

    def test_install_failure_rolls_back_both_sdk_and_privacy(self):
        before = hashes(self.output)
        replace = sdk.os.replace

        def fail_install(source, target):
            if Path(source).name == "new":
                raise OSError("injected install failure")
            replace(source, target)

        with patch.object(sdk.os, "replace", side_effect=fail_install):
            with self.assertRaisesRegex(OSError, "injected install failure"):
                sdk.import_sdk(self.source, self.output, "2.0.8")
        self.assertEqual(hashes(self.output), before)
        self.assertFalse((self.output.parent / ".wechat-sdk-import.lock").exists())

    def test_existing_import_lock_is_preserved(self):
        lock = self.output.parent / ".wechat-sdk-import.lock"
        lock.mkdir()
        with self.assertRaises(FileExistsError):
            sdk.import_sdk(self.source, self.output, "2.0.8")
        self.assertTrue(lock.is_dir())
        self.assertEqual((self.output / "previous.txt").read_bytes(), b"prior SDK")


if __name__ == "__main__":
    unittest.main()
