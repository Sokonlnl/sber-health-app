#!/usr/bin/env bash
# Локальная проверка на macOS (быстрый цикл вместо CI): SwiftLint, сборка,
# установка в запущенный симулятор и скриншоты всех экранов и состояний в build/local/<время>/.
# Использование:
#   scripts/local-verify.sh                 # сборка + скриншоты
#   scripts/local-verify.sh --tests         # плюс unit-тесты
#   SIM="iPhone 16 Pro" scripts/local-verify.sh
# Скриншоты потом сравнивает design-reviewer с docs/design/home-figma-63-25250.png.
set -euo pipefail

cd "$(dirname "$0")/.."
OUT="build/local/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
SCHEME=HealthMonitor
BUNDLE_ID=com.example.healthmonitor
SIM_NAME="${SIM:-}"

need() { command -v "$1" >/dev/null || { echo "Нет $1. Установи: brew install $2"; exit 1; }; }
need swiftlint swiftlint

echo "== SwiftLint --strict"
swiftlint --strict --quiet

# Симулятор: уже запущенный, иначе указанный в SIM, иначе первый доступный iPhone.
UDID=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -n1 || true)
if [ -z "$UDID" ]; then
  if [ -n "$SIM_NAME" ]; then
    UDID=$(xcrun simctl list devices available | grep "$SIM_NAME (" | grep -oE '[0-9A-F-]{36}' | head -n1)
  else
    UDID=$(xcrun simctl list devices available iPhone | grep -oE '[0-9A-F-]{36}' | head -n1)
  fi
  xcrun simctl boot "$UDID"
  open -a Simulator
fi
xcrun simctl bootstatus "$UDID" -b >/dev/null
echo "== Симулятор $UDID"

echo "== Сборка"
xcodebuild build \
  -project HealthMonitor.xcodeproj -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO -quiet | tee "$OUT/build.log"

APP=build/DerivedData/Build/Products/Debug-iphonesimulator/HealthMonitor.app
xcrun simctl install "$UDID" "$APP"

if [ "${1:-}" = "--tests" ]; then
  echo "== Unit-тесты"
  xcodebuild test \
    -project HealthMonitor.xcodeproj -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,id=$UDID" \
    -derivedDataPath build/DerivedData -only-testing:HealthMonitorTests \
    CODE_SIGNING_ALLOWED=NO -quiet | tee "$OUT/tests.log"
fi

echo "== Скриншоты"
for SCREEN in home pressure pressureSheet loading empty error; do
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" "$BUNDLE_ID" -uiScreen "$SCREEN" -uiTestsDisableIntro >/dev/null
  sleep 3
  xcrun simctl io "$UDID" screenshot "$OUT/$SCREEN.png" >/dev/null
  echo "   $OUT/$SCREEN.png"
done

# Приложение остаётся открытым на главном экране для ручной проверки (с заставкой).
xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl launch "$UDID" "$BUNDLE_ID" >/dev/null
echo "== Готово: $OUT"
