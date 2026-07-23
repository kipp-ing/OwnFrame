#!/bin/bash
#
# check-english-only.sh — enforce the project's "English source" rule for UI code.
#
# The source language is English: all Swift string literals, comments, and code stay
# English. Translations do NOT live in Swift — they live in the String Catalogs
# (.xcstrings), which is the one sanctioned place for other languages. So this script
# scans *Swift sources* for German and leaves the catalogs alone.
#
# Policy change (topic-300, 2026-07-23): German UI shipping is now enabled via the
# String Catalogs, so the former check that blocked any "de" localization in
# .xcstrings was removed. The remaining checks still guarantee that German never
# leaks into Swift source — it must be added as a catalog translation, never inline.
#
# Exits 2 when German is found in Swift so it can be wired as a Claude Code hook
# (exit 2 feeds the message back to the agent); exits 0 when clean. Safe in CI too.
#
# Deliberate exception: the diacritic test fixture "München Trip" (AlbumSearch
# folded-search coverage) is allow-listed.
#
set -uo pipefail

# Resolve repo root (this script lives in .claude/scripts/).
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT" || exit 0

fail=0
report() { echo "$1" >&2; echo "$2" >&2; fail=1; }

# German umlauts in Swift (high-signal). Allow the intentional "München" test fixture.
umlaut_hits="$(grep -rnE '[äöüÄÖÜß]' --include='*.swift' . 2>/dev/null | grep -v '/.build/' | grep -v 'München' || true)"
[ -n "$umlaut_hits" ] && report \
  "✗ German umlauts in Swift (translate to English):" \
  "$umlaut_hits"

# 3) Curated unambiguous German UI words inside string literals (catches ASCII-only German).
words='Weiter|Speichern|Verbinden|Verbindung|Abbrechen|Reihenfolge|Einstellungen|Einstellung|Quellen|Quelle|Fertig|Diashow|Schieben|Passwort|Benutzername|Geteilter|Geteilte|Hinzufügen|Entfernen|Anzeige|Anzeigedauer'
word_hits="$(grep -rnE "\"[^\"]*(${words})[^\"]*\"" --include='*.swift' . 2>/dev/null | grep -v '/.build/' || true)"
[ -n "$word_hits" ] && report \
  "✗ German UI words in Swift string literals (translate to English):" \
  "$word_hits"

if [ "$fail" -ne 0 ]; then
  echo "" >&2
  echo "english-always: all UI strings, comments, and code must be English. Fix the above." >&2
  exit 2
fi
exit 0
