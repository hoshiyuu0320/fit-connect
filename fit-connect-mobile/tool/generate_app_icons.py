#!/usr/bin/env python3
"""Resize the opaque master PNG into the existing iOS and Android app icons.

Run on macOS from fit-connect-mobile: python3 tool/generate_app_icons.py
Requires only Python 3 and the macOS sips utility.
"""

import json
from pathlib import Path
import shutil
import subprocess


MOBILE_ROOT = Path(__file__).resolve().parents[1]
SOURCE = MOBILE_ROOT / "assets/branding/fit-connect-app-icon.png"
IOS_CATALOG = MOBILE_ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
ANDROID_RES = MOBILE_ROOT / "android/app/src/main/res"
ANDROID_SIZES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}


def image_properties(path):
    result = subprocess.run(
        ["sips", "-g", "format", "-g", "pixelWidth", "-g", "pixelHeight", "-g", "hasAlpha", str(path)],
        check=True,
        capture_output=True,
        text=True,
    )
    return dict(line.strip().split(": ", 1) for line in result.stdout.splitlines() if ": " in line)


def main():
    if shutil.which("sips") is None:
        raise SystemExit("This script requires macOS sips.")
    if not SOURCE.is_file():
        raise SystemExit(f"Missing master icon: {SOURCE}")
    source_properties = image_properties(SOURCE)
    if (
        source_properties.get("format") != "png"
        or source_properties.get("hasAlpha") != "no"
        or source_properties.get("pixelWidth") != source_properties.get("pixelHeight")
        or int(source_properties.get("pixelWidth", 0)) < 1024
    ):
        raise SystemExit("Master icon must be a square PNG of at least 1024 px without an alpha channel.")

    outputs = {}
    catalog = json.loads((IOS_CATALOG / "Contents.json").read_text())
    for entry in catalog["images"]:
        width, height = (float(value) for value in entry["size"].split("x"))
        scale = float(entry["scale"].removesuffix("x"))
        pixels = width * scale
        if width != height or not pixels.is_integer():
            raise SystemExit(f"Unsupported icon dimensions: {entry}")
        outputs[IOS_CATALOG / entry["filename"]] = int(pixels)
    outputs.update(
        {ANDROID_RES / f"mipmap-{density}/ic_launcher.png": size for density, size in ANDROID_SIZES.items()}
    )

    for destination in outputs:
        if not destination.is_file():
            raise SystemExit(f"Expected existing icon is missing: {destination}")
    for destination, size in outputs.items():
        subprocess.run(
            ["sips", "-z", str(size), str(size), str(SOURCE), "--out", str(destination)],
            check=True,
            capture_output=True,
            text=True,
        )
        properties = image_properties(destination)
        if (
            properties.get("pixelWidth") != str(size)
            or properties.get("pixelHeight") != str(size)
            or properties.get("hasAlpha") != "no"
        ):
            raise SystemExit(f"Generated icon failed validation: {destination}")
        print(f"{destination.relative_to(MOBILE_ROOT)}: {size}x{size}, opaque")
    print(f"Generated and verified {len(outputs)} app icons.")


if __name__ == "__main__":
    main()
