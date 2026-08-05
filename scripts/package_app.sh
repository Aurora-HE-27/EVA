#!/bin/zsh
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
model_name="Qwen3.5-0.8B-MLX-4bit"
model_source="${EVA_MODEL_SOURCE:-/Users/hewenkai/AI开发/ai模型/huggingface/mlx-community/$model_name}"
model_link="$project_dir/Resources/Models/$model_name"
derived_data="$project_dir/DerivedData"
app_source="$derived_data/Build/Products/Release/EVA.app"
app_destination="$project_dir/dist/EVA.app"
created_link=0

if [[ ! -f "$model_source/config.json" ]]; then
    echo "未找到 EVA 本地模型：$model_source" >&2
    exit 1
fi

mkdir -p "$project_dir/Resources/Models"

if [[ -L "$model_link" ]]; then
    if [[ "$(readlink "$model_link")" != "$model_source" ]]; then
        echo "模型软链接指向了其他位置：$model_link" >&2
        exit 1
    fi
elif [[ -e "$model_link" ]]; then
    echo "模型目标已存在且不是软链接：$model_link" >&2
    exit 1
else
    ln -s "$model_source" "$model_link"
    created_link=1
fi

cleanup() {
    if [[ "$created_link" == "1" && -L "$model_link" ]]; then
        unlink "$model_link"
    fi
}
trap cleanup EXIT

cd "$project_dir"
xcodegen generate
resolved_destination="$project_dir/EVA.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
mkdir -p "$(dirname "$resolved_destination")"
cp "$project_dir/Package.resolved" "$resolved_destination"
xcodebuild \
    -project EVA.xcodeproj \
    -scheme EVA \
    -configuration Release \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$derived_data" \
    -skipPackagePluginValidation \
    -skipMacroValidation \
    CODE_SIGNING_ALLOWED=NO \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=YES \
    build

if [[ -e "$app_destination" ]]; then
    rm -rf "$app_destination"
fi
mkdir -p "$project_dir/dist"
ditto "$app_source" "$app_destination"
/usr/bin/codesign \
    --force \
    --deep \
    --sign - \
    --entitlements "$project_dir/Resources/EVA.entitlements" \
    "$app_destination"
/usr/bin/codesign --verify --deep --strict "$app_destination"
echo "$app_destination"
