# Quickstart / Validation: Shared-Link Onboarding & iOS Share Sheet

End-to-end validation scenarios mapped to FR/SC. Logic scenarios run on the host
(`swift test` in the relevant package); UI scenarios run via XcodeBuildMCP + XCUITest with the
`--uitest*` seams. Each row is the acceptance gate for the matching requirement.

## Prerequisites
- Host unit tests: `cd Packages/<Pkg> && swift test` (OnboardingKit, ImmichClient).
- UI: build the `Immich Slideshow` scheme on the pinned iOS 26.5 iPad sim; drive via `--uitest*` launch args.
- New seams to add (mirroring existing `--uitest*` ones): a way to start at `.choice`, to seed a
  shared-link-only library, to inject a pending shared link (App-Group store fake), and to seed 50+
  stub albums with date/count for the picker.

## A. Shared-link-only onboarding (US1)
| # | Scenario | Type | Asserts | FR / SC |
|---|----------|------|---------|---------|
| A1 | Fresh launch shows the choice screen with both options + descriptions | UI | `.choice` visible, two labeled options | FR-210-01, SC-210-08 |
| A2 | Pick "Use a shared link", enter a non-protected link → slideshow, no API key | host+UI | `StartupGate`/VM reach `.done`; keychain has no API key | FR-210-02/03/04, SC-210-01 |
| A3 | Password-protected link prompts once then starts | host+UI | resolve(nil)→`needsPassword`; confirm(pw)→saved; one prompt | FR-210-06, SC-210-02/03 |
| A4 | Malformed / non-HTTPS link errors before any network call | host | `.error`, transport not called | FR-210-09 |
| A5 | Invalid/expired/unreachable link → classified error, nothing persisted | host | distinct messages; library empty | FR-210-07/08, SC-210-05 |
| A6 | Relaunch of a shared-link-only setup goes straight to slideshow | host | `StartupGate.initialStep() == .done` (no key) | FR-210-04, SC-210-09 |

## B. iOS Share Sheet (US2)
| # | Scenario | Type | Asserts | FR / SC |
|---|----------|------|---------|---------|
| B1 | Extension extracts the URL from a shared item | host | `ShareLinkExtraction.url(from:)` returns the URL | FR-210-12/13 |
| B2 | Extension writes only the URL to the App Group; host consumes once | host | `savePendingURL`→`takePendingURL` returns it then `nil`; no secret stored | FR-210-13/18, SC-210-06 |
| B3 | Unconfigured + incoming link → shared-link setup pre-filled | host+UI | router `.prefillOnboarding`; setup shows the URL | FR-210-14 |
| B4 | Configured + new link → added + active, playback switches | host+UI | router `.addAndActivate`; active source = new link | FR-210-15 |
| B5 | Incoming link already in library → switch, no duplicate | host | router `.switchToExisting`; library count unchanged | FR-210-16, SC-210-07 |
| B6 | Protected incoming link prompts once then plays | host+UI | `needsPassword`→confirm→active | FR-210-06/15 |
| B7 | Malformed / non-Immich incoming link → error, nothing persisted | host | router `.invalid`; library unchanged | FR-210-17 |

## C. Searchable + subscrollable album picker (US3)
| # | Scenario | Type | Asserts | FR / SC |
|---|----------|------|---------|---------|
| C1 | Empty query returns all albums in order | host | `AlbumSearch.filter` identity | FR-210-19 |
| C2 | Name fragment narrows the list (case/diacritic-insensitive) | host | predicate matches name | FR-210-19, SC-210-04 |
| C3 | Date and photo-count queries match metadata | host | predicate matches date/count haystack | FR-210-19/20 |
| C4 | Albums missing date/count still match by name | host | predicate tolerates `nil` | FR-210-20 |
| C5 | No-match query shows an explicit empty state | UI | no-results view visible | FR-210-22 |
| C6 | 50+ albums: list scrolls, Continue/Add stays pinned (portrait+landscape) | UI (screenshot) | action visible while list scrolled | FR-210-21, SC-210-04 |

## D. Ask-password-only-when-needed everywhere (US4)
| # | Scenario | Type | Asserts | FR / SC |
|---|----------|------|---------|---------|
| D1 | Onboarding source step: non-protected link saves with no password field | host+UI | no password prompt; source saved | FR-210-06/11 |
| D2 | Settings → Sources: protected link prompts once, wrong pw is distinct | host+UI | `needsPassword`; `wrongPassword` error; nothing persisted | FR-210-07/11, SC-210-05 |
| D3 | Correct password stored only in the Keychain | host | secret store written; no plaintext elsewhere | FR-210-10, SC-210-06 |

## E. Descriptions (US5)
| # | Scenario | Type | Asserts | FR / SC |
|---|----------|------|---------|---------|
| E1 | Every onboarding screen shows concise helper text | UI | description present on choice/sharedlink/connection/album/confirm | FR-210-23, SC-210-08 |

## F. Cross-cutting / security
| # | Scenario | Type | Asserts | FR / SC |
|---|----------|------|---------|---------|
| F1 | No password / API key in UserDefaults, App Group, or logs | host+review | only the URL in the App Group; secrets only in Keychain | FR-210-10, SC-210-06 |
| F2 | All new flows run against fakes (no real server/Share Sheet/Keychain) | host | injected protocols; in-memory fakes | FR-210-24 |
| F3 | Album metadata reads validated against the running server's OpenAPI | manual | field names confirmed vs `/api/server/version` | FR-210-25 |

## Definition of Done (feature)
- Every row above green (host) or verified (UI/screenshot/manual).
- Full XCUITest suite green before merge (per project rule).
- A manual human-test pass of the real iOS Share Sheet round trip on device (the system Share Sheet
  cannot be driven by XCUITest), recorded in a `human-test-findings.md` like 120.
