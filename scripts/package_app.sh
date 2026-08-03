#!/bin/zsh
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="$project_dir/dist/EVA.app"
legacy_app_dir="$project_dir/dist/VirtualCompanion.app"
binary_path="$project_dir/.build/release/EVA"

swift build --package-path "$project_dir" -c release

mkdir -p "$app_dir/Contents/MacOS"
mkdir -p "$app_dir/Contents/Resources"
cp "$binary_path" "$app_dir/Contents/MacOS/EVA"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
codesign --force --deep --sign - "$app_dir"

if [[ -d "$legacy_app_dir" ]]; then
    rm -rf "$legacy_app_dir"
fi

echo "$app_dir"
