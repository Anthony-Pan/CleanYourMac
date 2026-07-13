//
//  CleanYourMacApp.swift
//  CleanYourMac — an open-source macOS cleanup app.
//
//  Built by Onyx (https://onyx-lab.com), the studio behind the app.
//  Open source (MIT); originally created by a middle-school student.
//  Contact: hello@onyx-lab.com  ·  ◈ An Onyx product
//

import SwiftUI
import AppKit
import CleanUI

/// Makes the SwiftPM executable behave like a normal, foreground macOS app
/// (Dock icon, focused window). Needed because a package executable has no
/// Info.plist to declare this.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct CleanYourMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("CleanYourMac") {
            RootView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}
