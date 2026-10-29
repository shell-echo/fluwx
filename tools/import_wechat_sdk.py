"""Repackage the official pay-enabled WeChat SDK as static-library XCFramework slices.

Run on macOS with Xcode tools installed. This copies vendor code unchanged and
never downloads code, edits a Pub cache, commits, or creates artificial dSYMs.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import signal
import subprocess
import tempfile


DEFAULT_OUTPUT = Path(__file__).resolve().parents[1] / "packages/fluwx/ios/fluwx/Frameworks/WechatSDK"
SLICES = {"ios-arm64": {"arm64"}, "ios-arm64_x86_64-simulator": {"arm64", "x86_64"}}
HEADERS = {"WXApi.h", "WXApiObject.h", "WechatAuthSDK.h", "WechatOpenSDK.h"}
MODULE_MAP = 'module WechatOpenSDK {\n    umbrella header "WechatOpenSDK/WechatOpenSDK.h"\n    export *\n}\n'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prepare(source, destination, version):
    if not re.fullmatch(r"\d+(?:\.\d+)+", version):
        raise ValueError("invalid SDK version")
    info = plistlib.loads((source / "Info.plist").read_bytes())
    libraries = info["AvailableLibraries"]
    if len(libraries) != 2 or {item["LibraryIdentifier"] for item in libraries} != set(SLICES):
        raise ValueError("expected the reviewed device and simulator slices")
    privacy = source / "PrivacyInfo.xcprivacy"
    plistlib.loads(privacy.read_bytes())
    allowed = {"Info.plist", "PrivacyInfo.xcprivacy", "README.txt"}
    provenance = {"version": version, "source_url": f"https://dldir1.qq.com/WechatWebDev/opensdk/XCFramework/OpenSDK{version}.zip", "sha256": {}}
    framework = destination / "WechatOpenSDK.xcframework"
    for item in libraries:
        identifier = item["LibraryIdentifier"]
        expected_variant = "simulator" if identifier.endswith("simulator") else None
        if (item["LibraryPath"] != "WechatOpenSDK.framework"
                or item["SupportedPlatform"] != "ios"
                or item.get("SupportedPlatformVariant") != expected_variant
                or set(item["SupportedArchitectures"]) != SLICES[identifier]):
            raise ValueError(f"unexpected SDK slice metadata: {identifier}")
        original = source / identifier / "WechatOpenSDK.framework"
        binary = original / "WechatOpenSDK"
        architectures = subprocess.check_output(["xcrun", "lipo", "-archs", str(binary)], text=True).split()
        if set(architectures) != SLICES[identifier]:
            raise ValueError(f"binary architectures differ from metadata: {identifier}")
        # A .framework name does not prove a static archive. Inspect every slice.
        for arch in architectures:
            thin = destination / f"inspect-{identifier}-{arch}.a"
            thin.parent.mkdir(parents=True, exist_ok=True)
            with binary.open("rb") as file:
                already_thin = file.read(8) == b"!<arch>\n"
            if already_thin:
                shutil.copy2(binary, thin)
            else:
                subprocess.run(["xcrun", "lipo", str(binary), "-thin", arch, "-output", str(thin)], check=True, capture_output=True)
            with thin.open("rb") as file:
                if file.read(8) != b"!<arch>\n":
                    raise ValueError(f"SDK is not a static archive: {identifier}/{arch}")
            thin.unlink()
        if {p.name for p in (original / "Headers").iterdir()} != HEADERS:
            raise ValueError("SDK headers changed; review the new public surface")
        target = framework / identifier
        target.mkdir(parents=True)
        shutil.copy2(binary, target / "libWechatOpenSDK.a")
        shutil.copytree(original / "Headers", target / "Headers/WechatOpenSDK")
        (target / "Headers/module.modulemap").write_text(MODULE_MAP)
        for name in ["WechatOpenSDK", "Info.plist", "Modules/module.modulemap", *[f"Headers/{h}" for h in HEADERS]]:
            allowed.add(f"{identifier}/WechatOpenSDK.framework/{name}")
        item.update(LibraryPath="libWechatOpenSDK.a", BinaryPath="libWechatOpenSDK.a", HeadersPath="Headers")
    # Fail if a newer SDK adds resources instead of silently discarding them.
    for path in source.rglob("*"):
        if path.is_symlink():
            raise ValueError(f"SDK contains a symlink: {path.name}")
        if path.is_file() and path.name != ".DS_Store":
            relative = path.relative_to(source).as_posix()
            if relative not in allowed:
                raise ValueError(f"unreviewed SDK resource: {relative}")
            provenance["sha256"][relative] = digest(path)
    (framework / "Info.plist").write_bytes(plistlib.dumps(info))
    resources = destination / "Privacy"
    resources.mkdir()
    shutil.copy2(privacy, resources / "PrivacyInfo.xcprivacy")
    (resources / "Privacy.swift").write_text("// Keep the original vendor privacy manifest in a SwiftPM resource bundle.\ninternal enum WechatOpenSDKPrivacy {}\n")
    if (source / "README.txt").is_file():
        shutil.copy2(source / "README.txt", destination / "README.vendor.txt")
    (destination / "provenance.json").write_text(json.dumps(provenance, sort_keys=True, indent=2) + "\n")


def import_sdk(source, output, version):
    source, output = Path(source).resolve(), Path(output).absolute()
    if output.is_symlink() or source == output.resolve() or source in output.resolve().parents or output.resolve() in source.parents:
        raise ValueError("SDK input and output must be separate, and output cannot be a symlink")
    output.parent.mkdir(parents=True, exist_ok=True)
    lock = output.parent / ".wechat-sdk-import.lock"
    lock.mkdir()  # An existing lock belongs to another or interrupted invocation.
    try:
        temporary = Path(tempfile.mkdtemp(prefix=".wechat-sdk-import-", dir=output.parent))
    except BaseException:
        lock.rmdir()
        raise
    preserve = False
    try:
        staged, backup = temporary / "new", temporary / "previous"
        prepare(source, staged, version)
        had_output = output.exists()
        try:
            if had_output:
                os.replace(output, backup)
            os.replace(staged, output)
        except BaseException:
            try:
                if backup.exists():
                    if output.exists():
                        shutil.rmtree(output)
                    os.replace(backup, output)
                elif not had_output and output.exists():
                    shutil.rmtree(output)
            except BaseException:
                preserve = True
                raise RuntimeError(f"rollback failed; retain {temporary} and {lock}")
            raise
    finally:
        if not preserve:
            shutil.rmtree(temporary)
            lock.rmdir()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="official WechatOpenSDK.xcframework directory")
    parser.add_argument("--version", required=True)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    def interrupted(received, _):
        raise SystemExit(128 + received)

    for signum in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(signum, interrupted)
    import_sdk(args.source, args.output, args.version)
    print(f"Packaged WeChat {args.version}: {args.output}")
