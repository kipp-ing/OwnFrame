# Privacy Policy — OwnFrame

Last updated: 2026-07-28

OwnFrame turns an iPhone, iPad, or Apple TV into a full-screen photo frame. It shows photos from
an [Immich](https://immich.app) server you control, from an Immich shared link, or from your own
Apple Photos / iCloud library. This policy is short because the app collects nothing.

## What the app collects

Nothing. The app has no analytics, no tracking, no advertising, no crash reporting to us, and
no account system. The developer never receives, sees, or stores any of your data.

## Where the app connects

The app makes network connections only to endpoints **you** configure, plus Apple services you
already use:

1. **Your Immich server** (or the server behind an Immich shared link you paste) — to load
   albums and photos over HTTPS.
2. **Your MQTT broker**, only if you set one up for Home Assistant control.
3. **Apple's iCloud**, only once the Apple TV app ships and you use it to sync setup — see
   "Syncing to Apple TV" below. No released version connects to iCloud for this.
4. **Apple's App Store**, only when you make a purchase or restore one — see "Purchases" below.

There are no connections to the developer or to any other third party.

## Credentials

Your Immich API key, shared-link passwords, and MQTT broker credentials are stored in the
device Keychain only. They are sent solely to the server they belong to and never appear in
logs or plain-text settings.

## Photos from your server

Photos are downloaded from your server for display and kept in a bounded on-device cache.
Nothing is uploaded anywhere.

If you configure Home Assistant control, the app publishes the current photo's **metadata**
(asset ID, capture date, location, album) to **your** MQTT broker. The photo **image** itself
is published only if you explicitly enable "Publish photo image to Home Assistant" — it is off
by default. Both topics are sent not retained, so they don't linger on the broker.

## Photos on your device

If you choose an album from your Apple Photos / iCloud library as a source, the app asks for
photo-library permission and reads **only** to display those photos on the frame. Your photos
are never uploaded, never sent to the developer, and never leave the device except by the two
routes you configure yourself: the Home Assistant image topic described above, if you turn it
on, and Apple's own iCloud sync, which is between you and Apple. You can revoke the permission
at any time in the system Settings.

The camera is used for exactly one thing: scanning a QR code to read a shared link during
setup. No image from the camera is stored or transmitted.

## Syncing to Apple TV

> **Not available yet.** The Apple TV app has not been released, and this sync is not active in
> any version you can install: the shipping build carries no iCloud entitlement, so it never
> writes your setup to iCloud. This section is published in advance so the disclosure is in place
> before the feature ships, and describes how it *will* work.

The Apple TV app will be able to pick up the configuration from your iPhone or iPad so you don't
have to type it in on a remote. It will travel through **your own iCloud account**, never through
the developer:

- Non-secret settings (server URL, chosen album, display options) via iCloud key-value
  storage.
- Secrets (API key, shared-link password, MQTT credentials) via CloudKit **encrypted
  fields**, which are end-to-end encrypted — Apple cannot read them either.

If you are not signed in to iCloud, sync simply won't happen and you configure the Apple TV
directly. Setting the Apple TV up by hand always stays possible.

## Purchases

The optional Supporter Unlock and the tips are one-time purchases handled entirely by Apple.
The developer receives no payment details, no card data, and no identity information — only
Apple's anonymous sales reports. Whether you own the unlock is cached on your device so an
unattended frame keeps working offline.

## Changes

Changes to this policy are visible in this repository's version history.

## Contact

Jan Kipping — app@kipp.ing
