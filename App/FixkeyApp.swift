// Copyright © 2026 Mehmet Ergene. Licensed under CC BY-NC 4.0: non-commercial use only, credit required. See LICENSE.

import SwiftUI

@main
struct FixkeyApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let mode = UserDefaults.standard.string(forKey: "FixkeyKeyboardPreview") {
                KeyboardPreviewScreen(mode: mode)
            } else {
                ContentView()
            }
            #else
            ContentView()
            #endif
        }
    }
}
