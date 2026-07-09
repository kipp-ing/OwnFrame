# Privacy Policy — Photo Frame for Immich

Last updated: 2026-07-09

Photo Frame for Immich is an iPad app that displays photos from an Immich server you control.
This policy is short because the app collects nothing.

## What the app collects

Nothing. The app has no analytics, no tracking, no advertising, no crash reporting to us, and
no account system. The developer never receives, sees, or stores any of your data.

## Where the app connects

The app makes network connections only to endpoints **you** configure:

1. **Your Immich server** (or the server behind an Immich shared link you paste) — to load
   albums and photos over HTTPS.
2. **Your MQTT broker**, only if you set one up for Home Assistant control.

There are no connections to the developer or to any third party.

## Credentials

Your Immich API key, shared-link passwords, and MQTT broker credentials are stored in the
device Keychain only. They are sent solely to the server they belong to and never appear in
logs or plain-text settings.

## Photos

Photos are downloaded from your server for display and kept in a bounded on-device cache.
Nothing is uploaded anywhere.

If you configure Home Assistant control, the app publishes the current photo's **metadata**
(asset ID, capture date, location, album) to **your** MQTT broker. The photo **image** itself
is published only if you explicitly enable "Publish photo image to Home Assistant" — it is off
by default. Both topics are sent not retained, so they don't linger on the broker.

## Changes

Changes to this policy are visible in this repository's version history.

## Contact

Jan Kipping — app@kipp.ing
