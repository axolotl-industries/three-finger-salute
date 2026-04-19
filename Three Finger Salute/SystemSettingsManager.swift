import Foundation
import AppKit
import Combine

class SystemSettingsManager: ObservableObject {
    static let shared = SystemSettingsManager()
    
    @Published var areGesturesDisabled: Bool = false
    
    private init() {
        checkStatus()
    }
    
    func checkStatus() {
        let process = Process()
        process.launchPath = "/usr/bin/defaults"
        process.arguments = ["-currentHost", "read", "NSGlobalDomain", "com.apple.trackpad.threeFingerVertSwipeGesture"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe() // Silence errors
        
        process.launch()
        process.waitUntilExit()
        
        if process.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                DispatchQueue.main.async {
                    self.areGesturesDisabled = (output == "0")
                }
            }
        } else {
            DispatchQueue.main.async {
                self.areGesturesDisabled = false
            }
        }
    }
    
    func optimizeSettings() {
        print("SystemSettingsManager: Optimizing trackpad settings...")
        
        let commands = [
            ["write", "com.apple.AppleMultitouchTrackpad", "TrackpadThreeFingerVertSwipeGesture", "-int", "0"],
            ["write", "com.apple.AppleMultitouchTrackpad", "TrackpadThreeFingerHorizSwipeGesture", "-int", "0"],
            ["write", "com.apple.driver.AppleBluetoothMultitouch.trackpad", "TrackpadThreeFingerVertSwipeGesture", "-int", "0"],
            ["write", "com.apple.driver.AppleBluetoothMultitouch.trackpad", "TrackpadThreeFingerHorizSwipeGesture", "-int", "0"],
            ["-currentHost", "write", "NSGlobalDomain", "com.apple.trackpad.threeFingerVertSwipeGesture", "-int", "0"],
            ["-currentHost", "write", "NSGlobalDomain", "com.apple.trackpad.threeFingerHorizSwipeGesture", "-int", "0"],
            ["write", "NSGlobalDomain", "AppleEnableSwipeNavigateWithScrolls", "-bool", "false"]
        ]
        
        for args in commands {
            let p = Process()
            p.launchPath = "/usr/bin/defaults"
            p.arguments = args
            p.launch()
            p.waitUntilExit()
        }
        
        // Restart Dock to apply changes
        let killDock = Process()
        killDock.launchPath = "/usr/bin/killall"
        killDock.arguments = ["Dock"]
        killDock.launch()
        killDock.waitUntilExit()
        
        // Restart cfprefsd to ensure settings are flushed
        let killPrefs = Process()
        killPrefs.launchPath = "/usr/bin/killall"
        killPrefs.arguments = ["cfprefsd"]
        killPrefs.launch()
        killPrefs.waitUntilExit()
        
        checkStatus()
    }
    
    func restoreSettings() {
        print("SystemSettingsManager: Restoring trackpad settings...")
        
        let commands = [
            ["write", "com.apple.AppleMultitouchTrackpad", "TrackpadThreeFingerVertSwipeGesture", "-int", "2"],
            ["write", "com.apple.AppleMultitouchTrackpad", "TrackpadThreeFingerHorizSwipeGesture", "-int", "2"],
            ["write", "com.apple.driver.AppleBluetoothMultitouch.trackpad", "TrackpadThreeFingerVertSwipeGesture", "-int", "2"],
            ["write", "com.apple.driver.AppleBluetoothMultitouch.trackpad", "TrackpadThreeFingerHorizSwipeGesture", "-int", "2"],
            ["-currentHost", "write", "NSGlobalDomain", "com.apple.trackpad.threeFingerVertSwipeGesture", "-int", "2"],
            ["-currentHost", "write", "NSGlobalDomain", "com.apple.trackpad.threeFingerHorizSwipeGesture", "-int", "2"],
            ["write", "NSGlobalDomain", "AppleEnableSwipeNavigateWithScrolls", "-bool", "true"]
        ]
        
        for args in commands {
            let p = Process()
            p.launchPath = "/usr/bin/defaults"
            p.arguments = args
            p.launch()
            p.waitUntilExit()
        }
        
        let killDock = Process()
        killDock.launchPath = "/usr/bin/killall"
        killDock.arguments = ["Dock"]
        killDock.launch()
        killDock.waitUntilExit()
        
        checkStatus()
    }
}
