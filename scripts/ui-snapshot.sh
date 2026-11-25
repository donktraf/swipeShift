#!/bin/bash
# ui-snapshot.sh — App-Screen im eigenen Simulator oeffnen und Screenshot (hell + dunkel) speichern.
#
#   scripts/ui-snapshot.sh <screen> [email] [KEY=VALUE …] [--no-build] [--out DIR] [--appearance light|dark|both] [--wait SEC]
#
# Beispiele:
#   scripts/ui-snapshot.sh worker.home
#   scripts/ui-snapshot.sh worker.jobDetail SS_DEBUG_JOB_ID=<id>
#   scripts/ui-snapshot.sh employer.dashboard --no-build
#   scripts/ui-snapshot.sh chat SS_DEBUG_CONVERSATION_ID=<id>
#
# Screens: worker.{home,radar,messages,swipe,profile,jobList,jobDetail,applications,calendar,financial,saved,
#   settings,notifications}, employer.{dashboard,postJob,jobs,applicants,calendar,financial,profile,settings,
#   notifications}, chat, admin.reports, auth.{landing,login,register} (auth.* ohne Token)
# Default-Konto: worker.* → test2@example.de, employer.* → workk1@example.de, admin.* → test1@example.de,
#   chat → test2@example.de (Employer-Chat: Konto explizit angeben)
# Voraussetzung: Backend laeuft auf localhost:3000 (npm run dev in swipeshift-backend/).
# Nutzt einen EIGENEN Simulator "SwipeShift-Snapshots" (wird nach dem Lauf nicht heruntergefahren).
# Ausgabe: <out>/<screen>-<light|dark>.png  (Default: siehe SNAP_ROOT)

set -euo pipefail

# Node vor der PATH-Einschraenkung suchen (npm run debug:token)
NODE_BIN="$(command -v node || true)"
# xcodebuild-Workaround: nur System-PATH (ohne swiftlint-Run-Script-Phase, die sonst den Build abbricht)
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SNAP_ROOT="${SS_SNAPSHOT_ROOT:-/private/tmp/claude-501/-Users-don-Developer-swift-projects-swipeShift/8afdb794-a046-4ad0-9684-cf50e8c65af4/scratchpad}"
SIM_NAME="SwipeShift-Snapshots"
BUNDLE_ID="com.swipeShift"

SCREEN=""; EMAIL=""; BUILD=1; OUT="$SNAP_ROOT/snapshots"; APPEARANCE="both"; WAIT=12
EXTRA_ENV=()

while [ $# -gt 0 ]; do
  case "$1" in
    --no-build) BUILD=0 ;;
    --out) OUT="$2"; shift ;;
    --appearance) APPEARANCE="$2"; shift ;;
    --wait) WAIT="$2"; shift ;;
    -h|--help) sed -n 2,20p "$0"; exit 0 ;;
    *=*) EXTRA_ENV+=("$1") ;;
    *@*) EMAIL="$1" ;;
    *) if [ -z "$SCREEN" ]; then SCREEN="$1"; else echo "Unbekanntes Argument: $1" >&2; exit 1; fi ;;
  esac
  shift
done
[ -n "$SCREEN" ] || { echo "Usage: $0 <screen> [email] [KEY=VALUE …] [--no-build] [--out DIR]" >&2; exit 1; }

if [ -z "$EMAIL" ]; then
  case "$SCREEN" in
    employer.*) EMAIL="workk1@example.de" ;;
    admin.*)    EMAIL="test1@example.de" ;;
    *)          EMAIL="test2@example.de" ;;
  esac
fi

mkdir -p "$OUT"

# 1) Simulator finden/anlegen (iPhone 17, neueste iOS-Runtime)
UDID="$(xcrun simctl list devices -j | python3 -c "
import json,sys
d=json.load(sys.stdin)['devices']
for rt,devs in d.items():
    for x in devs:
        if x['name']=='$SIM_NAME' and x.get('isAvailable',True): print(x['udid']); sys.exit()
")"
if [ -z "$UDID" ]; then
  RUNTIME="$(xcrun simctl list runtimes -j | python3 -c "
import json,sys
r=[x for x in json.load(sys.stdin)['runtimes'] if x.get('isAvailable') and x['identifier'].startswith('com.apple.CoreSimulator.SimRuntime.iOS-')]
r.sort(key=lambda x:[int(p) for p in x['version'].split('.')])
print(r[-1]['identifier'])
")"
  echo "Lege Simulator $SIM_NAME an ($RUNTIME)" >&2
  UDID="$(xcrun simctl create "$SIM_NAME" com.apple.CoreSimulator.SimDeviceType.iPhone-17 "$RUNTIME")"
fi

# 2) Booten (headless: kein Simulator.app-Fenster)
if ! xcrun simctl list devices | grep "$UDID" | grep -q "(Booted)"; then
  xcrun simctl boot "$UDID"
fi
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true

# 3) Bauen + installieren
APP="$SNAP_ROOT/DerivedData/Build/Products/Debug-iphonesimulator/swipeShift.app"
if [ "$BUILD" = 1 ]; then
  echo "Baue App (Debug)…" >&2
  xcodebuild -project "$ROOT/swipeShift.xcodeproj" -scheme swipeShift -configuration Debug \
    -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$SNAP_ROOT/DerivedData" \
    ENABLE_USER_SCRIPT_SANDBOXING=NO build > "$SNAP_ROOT/ui-snapshot-build.log" 2>&1 \
    || { tail -40 "$SNAP_ROOT/ui-snapshot-build.log" >&2; echo "Build fehlgeschlagen (Log: $SNAP_ROOT/ui-snapshot-build.log)" >&2; exit 1; }
fi
[ -d "$APP" ] || { echo "App nicht gefunden: $APP (ohne --no-build erneut ausfuehren)" >&2; exit 1; }
xcrun simctl install "$UDID" "$APP"

# 4) Token (nicht fuer auth.*)
TOKEN=""
case "$SCREEN" in
  auth.*) ;;
  *)
    [ -n "$NODE_BIN" ] || { echo "node nicht gefunden" >&2; exit 1; }
    TOKEN="$(cd "$ROOT/swipeshift-backend" && PATH="$(dirname "$NODE_BIN"):$PATH" npm run --silent debug:token -- "$EMAIL" 2>/dev/null | tail -1)"
    [ -n "$TOKEN" ] || { echo "Kein Token fuer $EMAIL (Backend-DB erreichbar? Konto vorhanden?)" >&2; exit 1; }
    ;;
esac

# 5) Statusbar vereinheitlichen
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularMode active --cellularBars 4 --wifiBars 3 --operatorName "" >/dev/null 2>&1 || true

# 6) Starten + Screenshot je Erscheinungsbild
case "$APPEARANCE" in both) MODES=(light dark) ;; *) MODES=("$APPEARANCE") ;; esac
for MODE in "${MODES[@]}"; do
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  ENVS=(SIMCTL_CHILD_SS_DEBUG_SCREEN="$SCREEN" SIMCTL_CHILD_SS_DEBUG_APPEARANCE="$MODE")
  [ -n "$TOKEN" ] && ENVS+=(SIMCTL_CHILD_SS_DEBUG_TOKEN="$TOKEN")
  # KEY=VALUE aus dem Aufruf (z.B. SS_DEBUG_JOB_ID=…) an die App durchreichen
  for kv in ${EXTRA_ENV[@]+"${EXTRA_ENV[@]}"}; do ENVS+=("SIMCTL_CHILD_$kv"); done
  env "${ENVS[@]}" xcrun simctl launch "$UDID" "$BUNDLE_ID" >/dev/null
  sleep "$WAIT"
  xcrun simctl io "$UDID" screenshot "$OUT/$SCREEN-$MODE.png" >/dev/null 2>&1
  echo "$OUT/$SCREEN-$MODE.png"
done

# App beenden, Simulator bleibt an
xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
