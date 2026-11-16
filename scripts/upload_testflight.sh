#!/usr/bin/env bash
#
# 归档 → 导出 ipa → 上传 TestFlight
#
# 必填：
#   export TEAM_ID=你的十位团队 ID
#   export BUNDLE_ID=com.yourname.filmsim      （可选，默认从 project.yml 读不到就报错）
#
# 上传凭证二选一：
#   A. App Store Connect API Key
#      export ASC_KEY_ID=XXXXXXXXXX
#      export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
#      export ASC_KEY_PATH=$HOME/private_keys/AuthKey_XXXXXXXXXX.p8
#   B. App 专用密码
#      export APPLE_ID=you@example.com
#      export APP_SPECIFIC_PASSWORD=abcd-efgh-ijkl-mnop
#
set -euo pipefail

SCHEME="FilmSim"
PROJECT="FilmSim.xcodeproj"
BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/FilmSim.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
IPA_PATH="$EXPORT_PATH/FilmSim.ipa"

if [[ -z "${TEAM_ID:-}" ]]; then
  echo "✗ 请先 export TEAM_ID=你的团队ID（developer.apple.com → Membership）" >&2
  exit 1
fi

if [[ ! -d "$PROJECT" ]]; then
  echo "✗ 找不到 $PROJECT，先运行：xcodegen generate" >&2
  exit 1
fi

mkdir -p "$BUILD_DIR"

echo "▸ 1/3 归档（Release）"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  -allowProvisioningUpdates \
  archive

echo "▸ 2/3 导出 ipa"
sed "s/YOURTEAMID/$TEAM_ID/" ExportOptions.plist > "$BUILD_DIR/ExportOptions.plist"
rm -rf "$EXPORT_PATH"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
  -allowProvisioningUpdates

if [[ ! -f "$IPA_PATH" ]]; then
  echo "✗ 没有生成 ipa，检查 ExportOptions.plist / 签名" >&2
  exit 1
fi

echo "▸ 3/3 上传 App Store Connect"
if [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" && -n "${ASC_KEY_PATH:-}" ]]; then
  xcrun altool --upload-app -f "$IPA_PATH" -t ios \
    --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
elif [[ -n "${APPLE_ID:-}" && -n "${APP_SPECIFIC_PASSWORD:-}" ]]; then
  # altool 会去钥匙串找私钥文件；新版把它拷到 ~/private_keys 下再用 --apiKey 更稳
  xcrun altool --upload-app -f "$IPA_PATH" -t ios \
    -u "$APPLE_ID" -p "$APP_SPECIFIC_PASSWORD"
else
  echo "✗ 缺少上传凭证：设置 ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH，或 APPLE_ID / APP_SPECIFIC_PASSWORD" >&2
  exit 1
fi

echo "✓ 上传完成。去 App Store Connect → TestFlight 等处理（5–30 分钟），然后添加测试员。"
