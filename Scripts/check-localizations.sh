#!/bin/sh
# Fails when the string catalogs are out of step with the source:
# - Localizable.xcstrings: a string the compiler extracts that has no
#   Russian, an entry for text that is gone, or an entry added by hand,
#   which Xcode never marks as gone;
# - InfoPlist.xcstrings: an entry for a key Info.plist doesn't have, or a
#   permission text (a *UsageDescription key) without Russian.
# Xcode's export syncs the catalogs with the source, in place and
# re-sorted, so they are checked after it and then put back as they were.
# Run after `xcodegen generate`. Extra arguments go to xcodebuild, such as
# CI's package flags.
set -eu

cd "$(dirname "$0")/.."
catalogs="Sources/Resources/Localizable.xcstrings Sources/Resources/InfoPlist.xcstrings"
work=$(mktemp -d)
for catalog in $catalogs; do
    cp "$catalog" "$work/$(basename "$catalog")"
done
trap 'for catalog in $catalogs; do cp "$work/$(basename "$catalog")" "$catalog"; done; rm -rf "$work"' EXIT

if ! xcodebuild -exportLocalizations \
    -project RDPeek.xcodeproj \
    -scheme RDPeek \
    -derivedDataPath DerivedData \
    -localizationPath "$work/export" \
    -exportLanguage ru \
    "$@" >"$work/export.log" 2>&1; then
    cat "$work/export.log"
    exit 1
fi

python3 -I - Sources/Resources Generated/Info.plist <<'EOF'
import json
import plistlib
import sys

resources, info_plist_path = sys.argv[1], sys.argv[2]


def load(name):
    return json.load(open(f"{resources}/{name}", encoding="utf-8"))["strings"]


def has_russian(entry):
    return "ru" in entry.get("localizations", {})


problems = []
strings = load("Localizable.xcstrings")
for key, entry in strings.items():
    state = entry.get("extractionState")
    if state == "stale":
        problems.append(f"Entry for text no longer in the source: {key!r}")
    elif state == "manual":
        problems.append(f"Entry added by hand, which Xcode never marks unused: {key!r}")
    elif entry.get("shouldTranslate", True) and not has_russian(entry):
        problems.append(f"No Russian for: {key!r}")

with open(info_plist_path, "rb") as info_plist:
    info_keys = set(plistlib.load(info_plist))
for key, entry in load("InfoPlist.xcstrings").items():
    if entry.get("extractionState") == "stale" or key not in info_keys:
        problems.append(f"InfoPlist entry for a key Info.plist doesn't have: {key!r}")
    elif key.endswith("UsageDescription") and not has_russian(entry):
        problems.append(f"No Russian for the permission text {key!r}")

for problem in problems:
    print(problem)
if problems:
    print(f"{len(problems)} catalog problem(s); see the Localization notes in AGENTS.md.")
    sys.exit(1)
print(f"Catalogs in step with the source: {len(strings)} strings, all translated.")
EOF
