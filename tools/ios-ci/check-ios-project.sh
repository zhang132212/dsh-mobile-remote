#!/usr/bin/env bash
# iOS 工程配置检查（信息性）：bundle id / deployment target / Info.plist 权限与文档类型 / 图标。
# 只做检查与记录，不修改文件；工程目录整体缺失时退出 1（此时构建也必然失败）。
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

: "${APP_DIR:?APP_DIR 未设置}"
REPORT="$CI_OUT/ios-project-report.txt"
PBX="$APP_DIR/ios/Runner.xcodeproj/project.pbxproj"
PLIST="$APP_DIR/ios/Runner/Info.plist"
ICONSET="$APP_DIR/ios/Runner/Assets.xcassets/AppIcon.appiconset"

step "ios-project-check"

if [ ! -f "$PBX" ]; then
  log "❌ 未找到 $PBX —— iOS 工程还没有提交/生成？"
  printf '❌ 未找到 %s\n' "$PBX" > "$REPORT"
  exit 1
fi

{
  echo "== iOS 工程配置检查（信息性）=="
  echo ""
  echo "-- 工程设置（project.pbxproj）--"
  grep -o 'PRODUCT_BUNDLE_IDENTIFIER = [^;]*' "$PBX" 2>/dev/null | sort -u | sed 's/^/  /'
  grep -o 'IPHONEOS_DEPLOYMENT_TARGET = [^;]*' "$PBX" 2>/dev/null | sort -u | sed 's/^/  /'
  grep -o 'SWIFT_VERSION = [^;]*' "$PBX" 2>/dev/null | sort -u | sed 's/^/  /'
  echo ""
  echo "-- Info.plist --"
  if [ -f "$PLIST" ]; then
    python3 - "$PLIST" <<'PY'
import plistlib
import sys

path = sys.argv[1]
try:
    with open(path, "rb") as handle:
        data = plistlib.load(handle)
except Exception as exc:  # noqa: BLE001 - 只做信息输出
    print("  读取失败:", exc)
    sys.exit(0)

checks = [
    "NSAppTransportSecurity",
    "NSLocalNetworkUsageDescription",
    "NSCameraUsageDescription",
    "NSPhotoLibraryUsageDescription",
    "CFBundleDocumentTypes",
    "CFBundleDisplayName",
]
for key in checks:
    print("  %-30s %s" % (key, "OK" if key in data else "缺失"))
print("  CFBundleDisplayName 值:", data.get("CFBundleDisplayName"))
ats = data.get("NSAppTransportSecurity") or {}
print("  NSAllowsArbitraryLoads:", ats.get("NSAllowsArbitraryLoads"))
print("  NSAllowsLocalNetworking:", ats.get("NSAllowsLocalNetworking"))
doc_types = data.get("CFBundleDocumentTypes") or []
for item in doc_types:
    print("  文档类型:", item.get("CFBundleTypeName"), item.get("LSItemContentTypes") or item.get("CFBundleTypeExtensions"))
if "UILaunchScreen" not in data and "UILaunchStoryboardName" not in data:
    print("  UILaunchScreen / UILaunchStoryboardName: 均缺失（启动图配置缺失）")
PY
  else
    echo "  ❌ Info.plist 不存在: $PLIST"
  fi
  echo ""
  echo "-- 应用图标 --"
  if [ -d "$ICONSET" ]; then
    echo "  PNG 数量: $(ls "$ICONSET"/*.png 2>/dev/null | wc -l | tr -d ' ')"
    echo "   1024 图标: $([ -f "$ICONSET/Icon-App-1024x1024@1x.png" ] && echo 存在 || echo 缺失)"
  else
    echo "  ❌ AppIcon.appiconset 不存在"
  fi
  echo ""
  echo "-- Podfile / SPM --"
  if [ -f "$APP_DIR/ios/Podfile" ]; then
    echo "  Podfile 存在"
  else
    echo "  Podfile 不存在（Flutter build 会自动从模板生成；首次 pod install 可能较慢）"
  fi
} > "$REPORT" 2>&1

cat "$REPORT" | tee -a "$BUILD_LOG"

# 期望值提示（不判失败）：bundle id 应为 com.dsh.remote
if grep -q 'PRODUCT_BUNDLE_IDENTIFIER = com.dsh.remote;' "$PBX" 2>/dev/null; then
  log "✅ bundle id = com.dsh.remote（符合计划）"
else
  log "⚠️ bundle id 还不是 com.dsh.remote（PLAN DoD 期望值），当前工程内取值见上"
fi
