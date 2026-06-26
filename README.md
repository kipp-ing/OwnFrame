# Immich Slideshow

A full-screen photo **slideshow app for iPad**, powered by your own
[Immich](https://immich.app) server. It is a standalone app — **not** a fork of the
official Immich client — and uses Immich purely as a photo source over its REST API.

> ⚠️ **Active development.** Onboarding, the full-screen slideshow, display/power control,
> and Home Assistant remote control are built; theme/display options (transitions, Ken Burns,
> clock overlay) are the next milestone. Home Assistant control is verified against an
> automated TLS broker test — live Home-Assistant confirmation is still pending.

## What it does (and will do)

- **Onboarding** — start from just a **shared link** (no account or API key) or connect to your
  server (URL + API key) to pick an album. You can also share an Immich link into the app from the
  iOS **Share Sheet** to set it up or switch sources. ✅ done
- **Slideshow** — full-screen, one photo at a time, with gentle cross-fades, reveal-on-tap
  controls, an album browser, and a photo-info overlay. ✅ done
- **Display & power** — keep the screen awake and dim brightness for ambient display. ✅ done
- **Home Assistant control** — adjust brightness, album, and play/pause over MQTT (TLS). ✅ done
- **Theme & display options** — transitions, Ken Burns, clock overlay, image fit. 🚧 planned

## Requirements

- An iPad running **iPadOS 18** or later.
- An **Immich server reachable over HTTPS with a valid TLS certificate.**
  (Self-signed / local certificates are not supported yet.)
- An Immich **API key** (Immich → Account Settings → API Keys) **only if you connect to your
  server** to browse albums — stored in the iOS **Keychain**, never in plain settings or logs.
  A **shared-link-only** setup needs no API key.

## Getting started

On first launch, choose how to connect:

- **Use a shared link** — paste an Immich share link (or share one into the app from another app).
  No account or API key needed; you're asked for a password only if the link has one.
- **Connect to a server** — enter your server address (HTTPS) and API key, then pick an album from
  a searchable list.

That's it — the app remembers your setup and skips straight to the slideshow on the next launch.
You can change the server connection (**Settings → Connection**), manage sources, or reset
everything to start over.

## Privacy & security

- Your API key and any shared-link password live only in the device Keychain. The API key is
  sent solely as the `x-api-key` header to **your** server; shared links use their own key.
- The app talks only to the Immich server you configure — no third parties.
- TLS is always validated; the app never disables certificate checks.

## For contributors

This project is built with Swift 6, SwiftUI, and Swift Package Manager, following a
spec-driven, test-first workflow.

- [docs/testing.md](docs/testing.md) — how the project is tested and how to run each layer.
- [docs/engineering-notes.md](docs/engineering-notes.md) — learnings, gotchas, and conventions.
- [CLAUDE.md](CLAUDE.md) — architecture, modules, constraints, and the working agreement.
