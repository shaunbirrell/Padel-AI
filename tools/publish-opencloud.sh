#!/usr/bin/env bash
# Publish dist/WarEmpire-PERF.rbxlx to an existing Roblox experience (Published).
# Requires: ROBLOX_OPEN_CLOUD_API_KEY, ROBLOX_UNIVERSE_ID, ROBLOX_PLACE_ID
# API key needs universe-places Write on that experience.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FILE="${ROBLOX_PLACE_FILE:-$ROOT/dist/WarEmpire-PERF.rbxlx}"
: "${ROBLOX_OPEN_CLOUD_API_KEY:?set ROBLOX_OPEN_CLOUD_API_KEY}"
: "${ROBLOX_UNIVERSE_ID:?set ROBLOX_UNIVERSE_ID}"
: "${ROBLOX_PLACE_ID:?set ROBLOX_PLACE_ID}"
test -f "$FILE" || { echo "missing place file: $FILE" >&2; exit 1; }
URL="https://apis.roblox.com/universes/v1/${ROBLOX_UNIVERSE_ID}/places/${ROBLOX_PLACE_ID}/versions?versionType=Published"
echo "Publishing $(basename "$FILE") ($(wc -c < "$FILE") bytes) → universe=${ROBLOX_UNIVERSE_ID} place=${ROBLOX_PLACE_ID}"
HTTP=$(curl -sS -o /tmp/we-publish-body.json -w "%{http_code}" -X POST "$URL" \
  -H "x-api-key: ${ROBLOX_OPEN_CLOUD_API_KEY}" \
  -H "Content-Type: application/xml" \
  --data-binary @"$FILE")
echo "HTTP $HTTP"
cat /tmp/we-publish-body.json; echo
case "$HTTP" in
  2*) echo "OK — open https://www.roblox.com/games/${ROBLOX_PLACE_ID} on mobile";;
  *) echo "FAIL" >&2; exit 1;;
esac
