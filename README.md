# Photo Frame for Immich & iCloud

Turns an iPad or iPhone into a full-screen **photo frame**. It supports devices down to
iOS 17 — a retired or cheap second-hand device makes a perfect frame. Setup really takes
seconds: pick an iCloud album, scan an Immich share QR code, or connect your Immich account.
No fiddling
with album creation inside the frame app — you keep managing albums in the app you already
know and like.

It is a standalone app — **not** a fork of the official Immich client, and it works
entirely without Immich if you use an iCloud album.

## Why it exists

This is a **hobby project** with a clear ambition: to show how to build a real, shippable
app cleanly with AI coding tools, using a **spec-driven, test-first workflow**. The lessons
learned along the way are documented in this repo.

The second reason: I didn't like the photo frame apps on the App Store. I wanted a
reasonably priced app that uses **already existing albums** and picks up changes
automatically — share pictures with your loved ones by simply updating your own album.
When this project started, that was either uncommon or uncommonly expensive.

## This is free

For the main use case. Additional features will cost a few bucks. The money covers my
costs: mostly the Apple Developer account, AI coding subscriptions, and dedicated test
hardware. If those costs are ever covered, everything beyond goes to the open source
community. That decision is mine alone — I prefer to sponsor the libraries that power
the tools most other projects rely on but that seldom get direct funding.

## What it does (and will do)

- **Onboarding** — start from just a **shared link** (no account or API key) or connect to your
  server (URL + API key) to pick an album. You can also share an Immich link into the app from the
  iOS **Share Sheet** to set it up or switch sources. ✅ done
- **Slideshow** — full-screen, one photo at a time, with gentle cross-fades, reveal-on-tap
  controls, an album browser, and a photo-info overlay. ✅ done
- **Display & power** — keep the screen awake and dim brightness for ambient display. ✅ done
- **Display options** — order, duration, transitions, Ken Burns, image fit, quality — applied
  live from Settings. ✅ done
- **Clock overlay** — Digits, Pill or Analog, six placements plus Random, two sizes; yields while
  the controls are showing, off by default. ✅ done on iPhone/iPad (tvOS rendering still to come)
- **Home Assistant control** — play/pause, brightness, album, every display setting,
  next/previous, current-photo metadata (image opt-in), and diagnostics over MQTT (TLS). ✅ done
- **Apple Photos / iCloud albums** — use an iCloud album as the source instead of (or alongside)
  Immich. ✅ done
- **Shortcuts & Siri** — play/pause, brightness, source switching and frame state as App Intents,
  usable in personal automations. 🧪 built, pending hardware verification
- **Apple TV** — the same frame on tvOS, set up without typing by syncing the iPad's
  configuration over iCloud. 🧪 built, pending hardware verification

## Requirements

- An iPad or iPhone running **iOS/iPadOS 17** or later (a retired device makes a good frame).
- For Immich sources: an **Immich server reachable over HTTPS with a valid TLS certificate.**
  (Self-signed / local certificates are not supported yet.) An iCloud-album source needs no
  server at all.
- An Immich **API key** (Immich → Account Settings → API Keys) **only if you connect to your
  server** to browse albums — stored in the iOS **Keychain**, never in plain settings or logs.
  A **shared-link-only** setup needs no API key.

## Getting started

On first launch, choose one of three ways in — ordered from least to most setup:

- **Use an iCloud album** — pick an album from your Photos library. No server, no account, no key.
- **Use a shared link** — **scan the album's QR code** with the camera, paste an Immich share link,
  or share one into the app from another app. No account or API key needed; you're asked for a
  password only if the link has one.
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
- **Home Assistant publishing (by design):** when the MQTT broker is configured, the app
  publishes the current photo's **metadata** (asset ID, capture date, location, album) to your
  broker so Home Assistant can display it. The photo **image** itself is published **only if you
  turn on "Publish photo image to Home Assistant"** in Settings → MQTT — it is **off by default**.
  Both photo topics are sent **not retained**, so neither the last photo nor what it depicted
  lingers on the broker. Broker credentials live only in the Keychain, never in logs.

## For contributors

This project is built with Swift 6, SwiftUI, and Swift Package Manager, following a
spec-driven, test-first workflow.

- [CONTRIBUTING.md](CONTRIBUTING.md) — contribution terms (licensing) and how to submit changes.
- [docs/testing.md](docs/testing.md) — how the project is tested and how to run each layer.
- [docs/engineering-notes.md](docs/engineering-notes.md) — learnings, gotchas, and conventions.
- [CLAUDE.md](CLAUDE.md) — architecture, modules, constraints, and the working agreement.

## License

[FSL-1.1-MIT](LICENSE) © 2026 Jan Kipping

[Fair Source](https://fair.io): the code is public — read it, build it, modify it, run it
yourself. What the [FSL](https://fsl.software) doesn't allow is offering a competing product
with it. Each release automatically becomes plain MIT two years after publication.
