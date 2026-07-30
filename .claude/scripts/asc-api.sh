#!/bin/bash
# App Store Connect API wrapper.
#
# Exists so the Claude Code permission rule can be narrow: allowing
# `Bash(.claude/scripts/asc-api.sh *)` grants exactly "talk to the ASC API as this team",
# nothing else — the base URL is hardcoded, the key comes from ~/.appstoreconnect.
#
# Usage: asc-api.sh METHOD PATH [JSON_BODY]
#   asc-api.sh GET  "/v1/apps/6784154405/appStoreVersions?filter[versionString]=1.1"
#   asc-api.sh PATCH "/v1/reviewSubmissions/<id>" '{"data":{...}}'
set -euo pipefail

METHOD=$1
APIPATH=$2
BODY=${3:-}

JWT=$(python3 ~/.appstoreconnect/asc_jwt.py)

args=(-sg -X "$METHOD" "https://api.appstoreconnect.apple.com${APIPATH}"
      -H "Authorization: Bearer $JWT")
if [[ -n "$BODY" ]]; then
  args+=(-H "Content-Type: application/json" -d "$BODY")
fi

curl "${args[@]}"
