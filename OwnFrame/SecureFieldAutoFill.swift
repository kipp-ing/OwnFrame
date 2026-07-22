//
//  SecureFieldAutoFill.swift
//  OwnFrame
//
//  The shared secret-entry field: a real `SecureField` in production, a plain
//  `TextField` under the hermetic `--uitest` launch seam. iOS pops a system
//  "Save Password?" sheet after any secure-field entry is submitted — it surfaces
//  nondeterministically (sometimes over the *next* screen or app launch) and
//  swallows every tap until dismissed, which breaks the XCUITest suite. Content-type
//  hints (`.oneTimeCode`) no longer suppress the sheet on iOS 26, so the tests avoid
//  the trigger instead: no secure field, no save offer. Production behavior is
//  untouched; none of the app's secrets are reusable web logins anyway (they live
//  in the device Keychain).
//

import SwiftUI

struct AppSecureField: View {
    let titleKey: LocalizedStringKey
    @Binding var text: String

    init(_ titleKey: LocalizedStringKey, text: Binding<String>) {
        self.titleKey = titleKey
        self._text = text
    }

    var body: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitest") {
            TextField(titleKey, text: $text)
        } else {
            SecureField(titleKey, text: $text)
        }
        #else
        SecureField(titleKey, text: $text)
        #endif
    }
}
