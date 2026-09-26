#!/bin/zsh
# immich-test-album.sh — one-time setup of the Immich album the device tests may WRITE to.
#
#   immich-test-album.sh            create (or find) the album, seed it, share it, store the link
#
# The album belongs to the test user on frame.kippings.de, never to Jan's own libraries, so the
# "a new server photo appears" test (DeviceArrivalUITests) can upload into it and clean up after
# itself. Seeds three flat photos: near-white and near-black (the #72/#60 glass stress cases) and
# a mid grey. Idempotent: an existing album of that name is reused and not re-seeded.
#
# Needs the upload-capable API key in the login Keychain item `ownframe-immich-upload`
# (account `immich-upload`). Writes the password-free shared link to the Keychain item
# `ownframe-test-album` (account = the link) — kept out of the public repo like the other links.
set -euo pipefail
SERVER="${IMMICH_SERVER:-https://frame.kippings.de}"
ALBUM="OwnFrame device test"
KEY="$(security find-generic-password -a immich-upload -s ownframe-immich-upload -w)"
api() { curl -sf -H "x-api-key: $KEY" "$@"; }
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

album_id=$(api "$SERVER/api/albums" | python3 -c "
import json,sys; print(next((a['id'] for a in json.load(sys.stdin) if a['albumName']=='$ALBUM'),''))")

if [ -z "$album_id" ]; then
  ids=()
  for spec in "f7f7f5 near-white" "0a0a0c near-black" "808080 mid-grey"; do
    hex=${spec%% *}; name=${spec#* }
    swift "$here/make-test-photo.swift" "$tmp/$name.jpg" "$hex" "OwnFrame test · $name"
    now=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
    id=$(api -F "assetData=@$tmp/$name.jpg;type=image/jpeg" -F "filename=$name.jpg" \
           -F "fileCreatedAt=$now" -F "fileModifiedAt=$now" "$SERVER/api/assets" \
         | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
    ids+=("$id")
  done
  album_id=$(api -H 'Content-Type: application/json' -X POST "$SERVER/api/albums" \
      -d "{\"albumName\":\"$ALBUM\",\"assetIds\":[\"${(j:",":)ids}\"]}" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
  echo "created album $album_id with ${#ids} photos"
else
  echo "album exists: $album_id"
fi

SLUG="ownframe-device-test"
slug=$(api "$SERVER/api/shared-links" | python3 -c "
import json,sys; print(next((l.get('slug') or '' for l in json.load(sys.stdin) if (l.get('album') or {}).get('id')=='$album_id'),''))")
if [ -z "$slug" ]; then
  slug=$(api -H 'Content-Type: application/json' -X POST "$SERVER/api/shared-links" \
      -d "{\"type\":\"ALBUM\",\"albumId\":\"$album_id\",\"slug\":\"$SLUG\",\"allowDownload\":true,\"showMetadata\":true}" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["slug"])')
fi
link="$SERVER/s/$slug"
security add-generic-password -U -a "$link" -s ownframe-test-album -w "$album_id"
echo "shared link stored in Keychain ownframe-test-album (album id as its secret)"
