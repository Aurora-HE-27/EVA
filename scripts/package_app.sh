#!/bin/zsh
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
model_root="${EVA_MODEL_ROOT:-$project_dir/.eva-models/huggingface}"
model_name="Qwen3.5-2B-MLX-4bit"
model_source="${EVA_MODEL_SOURCE:-$model_root/mlx-community/$model_name}"
model_link="$project_dir/Resources/Models/$model_name"
speech_model_name="Qwen3-TTS-12Hz-0.6B-CustomVoice-4bit"
speech_model_source="${EVA_SPEECH_MODEL_SOURCE:-$model_root/mlx-community/$speech_model_name}"
speech_model_link="$project_dir/Resources/Models/$speech_model_name"
derived_data="$project_dir/DerivedData"
app_source="$derived_data/Build/Products/Release/EVA.app"
app_destination="$project_dir/dist/EVA.app"
created_link=0
created_speech_link=0
package_staging=""

if [[ ! -f "$model_source/config.json" || ! -f "$speech_model_source/model.safetensors" || ! -f "$speech_model_source/speech_tokenizer/model.safetensors" ]]; then
    if [[ -n "${EVA_MODEL_SOURCE:-}" || -n "${EVA_SPEECH_MODEL_SOURCE:-}" ]]; then
        echo "指定的 EVA 模型目录不完整。" >&2
        exit 1
    fi
    EVA_MODEL_ROOT="$model_root" "$project_dir/scripts/download_eva_models.sh"
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

if [[ -L "$speech_model_link" ]]; then
    if [[ "$(readlink "$speech_model_link")" != "$speech_model_source" ]]; then
        echo "语音模型软链接指向了其他位置：$speech_model_link" >&2
        exit 1
    fi
elif [[ -e "$speech_model_link" ]]; then
    echo "语音模型目标已存在且不是软链接：$speech_model_link" >&2
    exit 1
else
    ln -s "$speech_model_source" "$speech_model_link"
    created_speech_link=1
fi

cleanup() {
    if [[ -n "$package_staging" && "$package_staging" == "$project_dir/dist/.eva-package."* && -d "$package_staging" ]]; then
        if [[ -d "$package_staging/previous.app" && ! -e "$app_destination" ]]; then
            mv "$package_staging/previous.app" "$app_destination"
        fi
        rm -rf "$package_staging"
    fi
    if [[ "$created_link" == "1" && -L "$model_link" ]]; then
        unlink "$model_link"
    fi
    if [[ "$created_speech_link" == "1" && -L "$speech_model_link" ]]; then
        unlink "$speech_model_link"
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

mkdir -p "$project_dir/dist"
package_staging="$(mktemp -d "$project_dir/dist/.eva-package.XXXXXX")"
staged_app="$package_staging/EVA.app"
ditto "$app_source" "$staged_app"
# Xcode's shared build directory may retain unit-test injection artifacts after
# `test`. They are not part of EVA and must not ship in the standalone app.
rm -rf "$staged_app/Contents/PlugIns/EVATests.xctest" "$staged_app/Contents/PlugIns/EVATests.xctest.dSYM"
for test_artifact in Testing.framework XCTAutomationSupport.framework XCTest.framework XCTestCore.framework XCTestSupport.framework XCUIAutomation.framework XCUnit.framework libXCTestBundleInject.dylib libXCTestSwiftSupport.dylib; do
    rm -rf "$staged_app/Contents/Frameworks/$test_artifact"
done
/usr/bin/codesign \
    --force \
    --deep \
    --sign - \
    --entitlements "$project_dir/Resources/EVA.entitlements" \
    "$staged_app"
/usr/bin/codesign --verify --deep --strict "$staged_app"

# Do not remove the usable app until its replacement has built and verified.
# The exit trap restores it if the final move fails, then removes temporary files.
if [[ -e "$app_destination" ]]; then
    mv "$app_destination" "$package_staging/previous.app"
fi
mv "$staged_app" "$app_destination"
echo "$app_destination"
