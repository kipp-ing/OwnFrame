//
//  FrameAppShortcuts.swift
//  OwnFrame
//
//  800 (T015): the App Shortcuts surface (FR-800-03) — intents work from Siri and
//  the Shortcuts app with zero manual setup. Five US1 shortcuts now, the two US3
//  ones land with T024; the platform cap is 10 and three slots stay deliberately
//  free for the Roadmap display-settings intents. Phrases are verb-first and all
//  carry the app name, keeping clear of HomeKit's device-control namespace.
//  No red-test pair: phrases are extracted metadata, manual-gated by SC-800-03.
//

import AppIntents

struct FrameAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PauseSlideshowIntent(),
            phrases: ["Pause \(.applicationName)"],
            shortTitle: "Pause",
            systemImageName: "pause.fill"
        )
        AppShortcut(
            intent: ResumeSlideshowIntent(),
            phrases: ["Resume \(.applicationName)"],
            shortTitle: "Resume",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: NextPhotoIntent(),
            phrases: ["Next photo on \(.applicationName)"],
            shortTitle: "Next Photo",
            systemImageName: "forward.fill"
        )
        AppShortcut(
            intent: PreviousPhotoIntent(),
            phrases: ["Previous photo on \(.applicationName)"],
            shortTitle: "Previous Photo",
            systemImageName: "backward.fill"
        )
        AppShortcut(
            intent: SetBrightnessIntent(),
            phrases: ["Set \(.applicationName) brightness"],
            shortTitle: "Set Brightness",
            systemImageName: "sun.max.fill"
        )
        AppShortcut(
            intent: SelectSourceIntent(),
            phrases: ["Set \(.applicationName) source"],
            shortTitle: "Set Source",
            systemImageName: "photo.on.rectangle"
        )
        AppShortcut(
            intent: GetFrameStateIntent(),
            phrases: ["Get \(.applicationName) state"],
            shortTitle: "Frame State",
            systemImageName: "info.circle"
        )
    }
}
