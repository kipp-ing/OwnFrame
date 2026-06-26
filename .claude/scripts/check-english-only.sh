#!/bin/bash
#
# check-english-only.sh — enforce the project's "English always" rule for UI code.
#
# Scans Swift sources and String Catalogs (.xcstrings) for German and prints any
# offenders. Scoped to code + UI strings on purpose: it does NOT scan Markdown, so
# legacy German specs/docs don't trip it. Exits 2 when German is found so it can be
# wired as a Claude Code hook (exit 2 feeds the message back to the agent); exits 0
# when clean. Safe to run manually or in CI too.
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

# 1) German "de" localizations in String Catalogs — definitive (source language is en).
de_hits="$(grep -rn '"de" :' --include='*.xcstrings' . 2>/dev/null | grep -v '/.build/' || true)"
[ -n "$de_hits" ] && report \
  "✗ German 'de' localizations in String Catalogs (remove them — English is the source language):" \
  "$de_hits"

# 2) German umlauts in Swift (high-signal). Allow the intentional "München" test fixture.
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
