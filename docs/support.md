# OwnFrame — Support

**OwnFrame** turns an iPad or iPhone into a full-screen photo frame for your own
[Immich](https://immich.app) server, an Immich shared link, or an iCloud album.

## Getting help

- **Questions & bug reports:** open an issue at
  <https://github.com/kipp-ing/OwnFrame/issues>.
- **Email:** [app@kipp.ing](mailto:app@kipp.ing).

When reporting a problem, it helps to include your device and iOS/iPadOS version, how
your source is set up (shared link, server + API key, or iCloud album), and what you
expected to happen versus what did.

## Common topics

- **Setup.** On first launch you can start from an iCloud album, an Immich shared link
  (scan its QR code, paste it, or share it into the app), or a server connection (server
  URL + API key). A shared link needs no account or API key; you're asked for a password
  only if the link has one.
- **Requirements.** For Immich sources you need an Immich server reachable over **HTTPS
  with a valid TLS certificate**. Self-signed / local certificates are not supported yet.
  An iCloud-album source needs no server at all.
- **Credentials.** Your API key and any shared-link password are stored only in the device
  Keychain, and are never written to logs or plain settings.
- **Home Assistant.** OwnFrame can appear in Home Assistant over MQTT (TLS) for telemetry
  and remote control. See the in-app Settings for broker configuration.

## Privacy

OwnFrame talks only to the server (and optional MQTT broker) you configure — no third
parties, and no analytics. See the [Privacy Policy](privacy-policy.md).
