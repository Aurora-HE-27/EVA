#!/bin/zsh

set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"

if [[ "$(/usr/bin/uname -m)" != "arm64" ]]; then
  echo "EVA 需要 Apple Silicon Mac。" >&2
  exit 1
fi

if [[ ! -d /Applications/Xcode.app ]]; then
  echo "请先从 App Store 安装完整 Xcode。" >&2
  exit 1
fi

if ! /usr/bin/xcrun --find xcodebuild >/dev/null 2>&1; then
  echo "请先运行：sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "缺少 XcodeGen。安装 Homebrew 后运行：brew install xcodegen" >&2
  exit 1
fi

"$project_dir/scripts/verify_model_sources.sh"
"$project_dir/scripts/package_app.sh"

echo "EVA 已重构完成：$project_dir/dist/EVA.app"
