import SwiftUI
import ServiceManagement
import AppKit

@main
struct ThreeFingerSaluteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

struct SettingsView: View {
    @AppStorage("isVolumeSwipeEnabled") private var isVolumeSwipeEnabled = true
    @AppStorage("isMiddleClickEnabled") private var isMiddleClickEnabled = true
    @AppStorage("swipeSensitivity") private var swipeSensitivity = 1.2
    
    var body: some View {
        Form {
            Section("Features") {
                Toggle("Three-Finger Volume Swipe", isOn: $isVolumeSwipeEnabled)
                Toggle("Three-Finger Middle Click", isOn: $isMiddleClickEnabled)
            }
            
            Section("Sensitivity") {
                VStack(alignment: .leading) {
                    Slider(value: $swipeSensitivity, in: 0.5...2.5, step: 0.1) {
                        Text("Swipe Sensitivity")
                    }
                    Text("Current: \(String(format: "%.1f", swipeSensitivity))x")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Divider()
            
            VStack(alignment: .center, spacing: 5) {
                Text("Three Finger Salute")
                    .font(.headline)
                Text("by Axolotl Industries")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Version 1.1.1")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Link(destination: URL(string: "https://ko-fi.com/axolotlindustries")!) {
                    Label("Support on Ko-Fi", systemImage: "cup.and.saucer.fill")
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(8)
                }
                .padding(.top, 10)
            }
            .frame(maxWidth: .infinity)
            .padding(.top)
        }
        .formStyle(.grouped)
        .frame(width: 350, height: 420)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    private let loginService = SMAppService.mainApp

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("Three Finger Salute: Launched")
        
        let hasLaunchedBefore = UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        let isTrusted = AXIsProcessTrusted()
        
        if !hasLaunchedBefore || !isTrusted {
            showOnboarding()
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
        }
        
        GestureController.shared.start()
        setupStatusItem()
        setupSleepWakeObservers()

        VolumeManager.shared.onChange = { [weak self] volume, muted in
            self?.updateIcon(volume: volume, muted: muted)
        }
    }
    
    private var onboardingWindow: NSWindow?
    
    private func showOnboarding() {
        if let window = onboardingWindow {
            window.makeKeyAndOrderFront(nil)
            return
        }
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 600),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Welcome to Three Finger Salute"
        
        DispatchQueue.main.async {
            window.contentView = NSHostingView(rootView: OnboardingView())
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
        
        self.onboardingWindow = window
    }

    private func setupSleepWakeObservers() {
        // screensDidWake fires on every monitor wake, which is too aggressive
        // for a full MT framework + event tap restart. didWake (system sleep)
        // is the case where MT can actually go stale.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            print("Three Finger Salute: System woke up, refreshing connections in 2 seconds...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                GestureController.shared.restart()
            }
        }
    }


    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon(volume: VolumeManager.shared.getVolume(), muted: VolumeManager.shared.isMuted())
        setupMenu()
    }

    private func updateIcon(volume: Float, muted: Bool) {
        guard let button = statusItem?.button else { return }
        let showMutedIcon = muted || volume == 0
        let iconName = showMutedIcon ? "speaker.slash.circle.fill" : "3.circle.fill"
        button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Three Finger Salute")
    }


    private func setupMenu() {
        let menu = NSMenu()

        let titleItem = NSMenuItem(title: "Three Finger Salute", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings(_:)), keyEquivalent: ","))
        
        menu.addItem(NSMenuItem.separator())
        
        // Launch at Login Toggle
        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLoginSheet(_:)), keyEquivalent: "l")
        loginItem.state = loginService.status == .enabled ? .on : .off
        menu.addItem(loginItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem?.menu = menu
    }
    
    @objc private func openSettings(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        // For SwiftUI Apps, we can use a dedicated window for Settings to ensure it opens reliably
        showSettingsWindow()
    }
    
    private var settingsWindow: NSWindow?
    
    private func showSettingsWindow() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            return
        }
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 350, height: 480),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Three Finger Salute Settings"
        window.isReleasedWhenClosed = false
        
        // Use a slight delay or async to avoid layout recursion issues on some systems
        DispatchQueue.main.async {
            window.contentView = NSHostingView(rootView: SettingsView())
            window.makeKeyAndOrderFront(nil)
        }
        
        self.settingsWindow = window
    }
    
    @objc private func toggleLoginSheet(_ sender: NSMenuItem) {
        do {
            if loginService.status == .enabled {
                try loginService.unregister()
                sender.state = .off
            } else {
                try loginService.register()
                sender.state = .on
            }
        } catch {
            print("Failed to update login service: \(error)")
        }
    }
}
