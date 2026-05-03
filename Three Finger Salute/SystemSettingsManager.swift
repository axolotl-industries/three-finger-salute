import Foundation
import AppKit
import Combine

class SystemSettingsManager: ObservableObject {
    static let shared = SystemSettingsManager()

    @Published var areGesturesDisabled: Bool = false

    // Both per-app and global keys gate the trackpad swipe behavior. Writing
    // each in its appropriate (host, user) scope and then bouncing Dock is
    // enough — no need to spawn `defaults` or kill cfprefsd.
    private static let perAppDomains = [
        "com.apple.AppleMultitouchTrackpad",
        "com.apple.driver.AppleBluetoothMultitouch.trackpad"
    ]
    private static let perAppKeys = [
        "TrackpadThreeFingerVertSwipeGesture",
        "TrackpadThreeFingerHorizSwipeGesture"
    ]
    private static let globalGestureKeys = [
        "com.apple.trackpad.threeFingerVertSwipeGesture",
        "com.apple.trackpad.threeFingerHorizSwipeGesture"
    ]
    private static let globalDomain = "NSGlobalDomain" as CFString

    private init() {
        checkStatus()
    }

    func checkStatus() {
        let value = CFPreferencesCopyValue(
            Self.globalGestureKeys[0] as CFString,
            Self.globalDomain,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        ) as? Int
        let disabled = (value == 0)
        DispatchQueue.main.async { self.areGesturesDisabled = disabled }
    }

    func optimizeSettings() {
        print("SystemSettingsManager: Optimizing trackpad settings...")
        apply(gestureValue: 0, swipeNavigateWithScrolls: false)
    }

    func restoreSettings() {
        print("SystemSettingsManager: Restoring trackpad settings...")
        apply(gestureValue: 2, swipeNavigateWithScrolls: true)
    }

    private func apply(gestureValue: Int, swipeNavigateWithScrolls: Bool) {
        let intValue = gestureValue as CFNumber

        for domain in Self.perAppDomains {
            for key in Self.perAppKeys {
                CFPreferencesSetValue(
                    key as CFString, intValue, domain as CFString,
                    kCFPreferencesCurrentUser, kCFPreferencesAnyHost
                )
            }
            CFPreferencesAppSynchronize(domain as CFString)
        }

        for key in Self.globalGestureKeys {
            CFPreferencesSetValue(
                key as CFString, intValue, Self.globalDomain,
                kCFPreferencesCurrentUser, kCFPreferencesCurrentHost
            )
        }
        CFPreferencesSynchronize(
            Self.globalDomain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost
        )

        let boolValue: CFBoolean = swipeNavigateWithScrolls ? kCFBooleanTrue : kCFBooleanFalse
        CFPreferencesSetValue(
            "AppleEnableSwipeNavigateWithScrolls" as CFString,
            boolValue,
            Self.globalDomain,
            kCFPreferencesCurrentUser, kCFPreferencesAnyHost
        )
        CFPreferencesAppSynchronize(Self.globalDomain)

        // Trackpad driver re-reads these prefs after Dock is restarted.
        let killDock = Process()
        killDock.launchPath = "/usr/bin/killall"
        killDock.arguments = ["Dock"]
        try? killDock.run()
        killDock.waitUntilExit()

        checkStatus()
    }
}
