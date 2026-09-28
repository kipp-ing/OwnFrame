# Human test checklist — Source Library (120)

Manual QA on a **real iPad + real Immich** (Immich 2.7.x, valid TLS cert). The automated suite
(OnboardingKit host tests + XCUITest) already proves the logic and the hermetic UI flow; this
checklist verifies the parts a human must judge: real network, the real Keychain, real shared links,
and visual polish. Tick each box; note the build/commit and device.

- **Build/commit under test:** `spec/120-source-library` @ `___________`  (PR #8)
- **Device / iPadOS:** `___________`
- **Immich server:** `___________`  · **API key created** (Account → API Keys)
- **Real shared links:** unprotected `https://<host>/s/geo2026` · protected
  `https://<host>/s/korsika2026` (password `12345678`)

> **Status 2026-09-28 — superseded; do not run this list as a whole.** Written for PR #8, before
> the welcome screen (220) and link-first onboarding (210). Where each part lives now:
> - §1 / §2 onboarding: device acceptance on real hardware (`device-accept.sh`: demo link,
>   protected link with a wrong then right password, 4/4 on iPad jk) plus `SourceOnboardingUITests`
>   / `SharedLinkOnboardingUITests` in the simulator. The "Connection screen first" flow no longer exists.
> - §3 source manager: `SourceLibraryUITests` (add/remove, switch swaps the running slideshow);
>   rename, duplicate names and reorder in `SourceLibraryTests` / `SourceLibraryViewModelTests`
>   (host); a real source switch on device by `device-accept.sh <udid> ha-parity`.
> - §4 upgrade from a pre-120 build: obsolete — no pre-120 build was ever released.
> - §5 logs: `LOGCHECK=1 device-accept.sh` records the device log during the link tests and fails
>   on the password or a share key in any OwnFrame process line. Reset leaving link passwords
>   behind is issue #73.
> - §6 robustness: resilience + availability runs (hitl §4); orientation by the simulator suites.

> Fresh start: delete the app first (or Settings → Reset) so onboarding runs from step 1.

## 1. Onboarding — album source (US2)
- [ ] Launch fresh → **Connection** screen (server URL + API key, single **Continue**).
- [ ] Enter a bad URL / wrong key → Continue shows a clear error, stays on the screen, **no** crash.
- [ ] Enter the real URL + key → Continue advances to **Add a source**.
- [ ] **Album** segment is selected; the server's real albums are listed.
- [ ] Tap an album → it appears under "Added sources" with a checkmark; **Continue** appears.
- [ ] Continue → **Confirm** lists the album, marked **Active**.
- [ ] **Start slideshow** → the chosen album's photos play.

## 2. Onboarding — shared-link source (US2)
Re-run onboarding (Reset, or a second device):
- [ ] On **Add a source**, switch to **Shared link**.
- [ ] Paste the **unprotected** link (`…/s/geo2026`), give it a name, **Add** → no error, source added.
- [ ] (Optional) also add the **protected** link (`…/s/korsika2026`) with password `12345678` → added.
- [ ] Wrong password on the protected link → clear "wrong password" error; **nothing** is saved.
- [ ] Malformed URL (not `https://host/s/slug`) → clear validation error.
- [ ] Continue → Confirm → **Start** → the shared link's photos play **without** using your API key.

## 3. Settings — Sources manager (US2 / US1)
From the running slideshow → reveal chrome → Settings → **Quellen**:
- [ ] The active source is marked; the list matches what was added.
- [ ] **Add** an album → appears in the list.
- [ ] **Add** a shared link (URL + optional password) → validated, appears in the list.
- [ ] Tap a non-active source → it becomes active; close Settings → the **running slideshow swaps**
      to that source's photos within a few seconds.
- [ ] Switch album→album: transition is quick (no full reload flash).
- [ ] Switch album↔shared-link: slideshow rebuilds and plays the new source.
- [ ] **Swipe** a row → **Umbenennen** (rename) and **Löschen** (delete) work; a duplicate name is
      rejected with a clear message.
- [ ] **Edit / reorder** the list → order persists.
- [ ] Remove the **active** source → the next source becomes active and plays; removing the last one
      returns to onboarding/empty state.

## 4. Persistence & migration (US4)
- [ ] Force-quit and relaunch → the **same** library + active source restore; the slideshow resumes
      the active source (no re-onboarding).
- [ ] **Upgrade path:** install a pre-120 build, finish onboarding with one album, then install this
      build → the old album appears as a one-entry **active** source; the slideshow keeps playing it.

## 5. Security / hygiene (Konstitution III)
- [ ] After adding a password-protected link, neither the password nor a bearer key is visible in any
      exported diagnostics/logs (passwords live only in the Keychain; check the device console if able).
- [ ] Reset (Settings → Reset) clears the library, returns to Connection, and the API key is gone.

## 6. Robustness
- [ ] Server unreachable mid-show → the existing error/retry handling still applies (no crash).
- [ ] A server with **no albums** still lets you finish onboarding by adding a **shared link**.
- [ ] Both **portrait and landscape**: onboarding, the Sources manager, and the slideshow render
      correctly (no clipped controls).

## Not yet in scope (do not test here)
- **Home Assistant source select** (US3, tasks T023–T026) — not built yet.
- Disk image cache / auto-retry backoff / periodic refresh / clock overlay (carried-over 300/500).

---
**Result:** ☐ Pass ☐ Pass with notes ☐ Fail — notes:
