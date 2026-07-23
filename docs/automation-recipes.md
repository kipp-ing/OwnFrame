# Automation Recipes: Controlling the Frame with Shortcuts & Siri

OwnFrame exposes its remote-control commands as **App Intents** — the
same commands Home Assistant drives (see `docs/`, topic 700), available to Siri, the
Shortcuts app, and on-device **personal automations**. No broker, no network, no
extra hardware: the frame schedules itself.

## What you can say / run

All actions appear in the Shortcuts app automatically after installing the app
(no setup), and respond to Siri with the app name in the phrase:

| Action | Siri phrase | Notes |
|---|---|---|
| Pause Slideshow | "Pause OwnFrame" | Same semantics as the on-screen pause |
| Resume Slideshow | "Resume OwnFrame" | |
| Next Photo | "Next photo on OwnFrame" | Steps while paused without resuming |
| Previous Photo | "Previous photo on OwnFrame" | |
| Set Frame Brightness | "Set OwnFrame brightness" | 0–100 % |
| Set Frame Source | "Set OwnFrame source" | Options = your saved sources |
| Get Frame State | "Get OwnFrame state" | Returns playing/paused, brightness, source, photo date & place |

The spoken phrases are localized (`OwnFrame/AppShortcuts.xcstrings`); on a German device
Siri answers to the German wording instead, and Get Frame State reads the play state back
in the device language.

## The two assumptions (read this first)

1. **The app must be in the foreground.** iOS only lets an app control screen
   brightness and the sleep timer while it is the frontmost app. Every control
   action therefore *opens the frame app* if it isn't already front — and on a
   dedicated frame iPad it always is. Get Frame State never opens the app; if the
   frame isn't running it reports an error instead of guessing.
2. **The device must be unlocked when the automation fires.** A dedicated frame
   never locks (see the setup below). If you try these on a locked iPad, iOS will
   hold the automation until you unlock.

Recommended frame setup: Settings → Displays & Brightness → Auto-Lock **Never**
(or use Guided Access), the app running fullscreen, charger connected.

## Recipe: night dim / morning wake

The frame dims to black and pauses at 22:00, and wakes at 07:00 — entirely on
device.

**Night (22:00):**

1. Shortcuts app → **Automation** → **+** → **Time of Day** → 22:00, Daily.
2. Turn **Ask Before Running OFF** (this is what makes it unattended — confirm
   with "Don't Ask").
3. Add action **Set Frame Brightness** → 0.
4. Add action **Pause Slideshow**.

**Morning (07:00):** same steps with **Set Frame Brightness** → 60 and
**Resume Slideshow**.

Run each shortcut once by hand to verify, then let the schedule take over. The
frame stays foreground the whole time; the screen never truly turns *off* (iOS
offers no API for that) — brightness 0 is the darkest an app can go. If you want
the backlight physically off, that remains a job for a smart plug or Home
Assistant.

Other triggers that work the same way: **Charger Connected / Disconnected**,
**NFC tag**, **Focus on/off**, **Alarm stopped**. Anything time- or device-local.

## Branching on frame state

**Get Frame State** returns a structured result you can branch on in Shortcuts
(If → "Is Playing is false" → …). Fields: Is Playing, Brightness Percent, Source
Label, Photo Date, Photo City, Photo Country. Nothing else — no image data, no
server details. City/country are empty for Apple Photos sources (the app does no
geocoding of your library).

## The HomeKit boundary (what does NOT work)

Apple does not let iPad apps act as HomeKit accessories, and home hubs do not run
third-party intents:

- ❌ A HomeKit **accessory event** (motion sensor, smart button) cannot trigger
  these intents directly.
- ❌ A **Home app automation** running on a hub (HomePod/Apple TV) cannot call
  them either — personal automations run on the frame device itself.
- ✅ If you run **Home Assistant**, its HomeKit Bridge can re-expose the frame's
  MQTT entities (topic 700) to Apple Home — then "Hey Siri, set the frame light
  to 40 %" works through HA, and any HomeKit accessory can drive the frame via an
  HA automation. That path needs no code from this app beyond the existing MQTT
  support.

## Errors you might see

- "Set up the frame first — open OwnFrame and add a source." — the app has
  never finished onboarding.
- "OwnFrame must be open on the frame device for this." — the app wasn't
  running (or was still starting) when the action ran.
- "Brightness must be between 0 and 100 percent." — a Shortcuts variable fed an
  out-of-range number; the frame state is unchanged.
- "This source no longer exists in the frame's library." — an automation
  references a deleted source; the current source keeps playing.
