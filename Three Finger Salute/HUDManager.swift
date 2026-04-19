import SwiftUI
import AppKit

class HUDManager {
    static let shared = HUDManager()
    private var hudWindow: NSPanel?
    private var hideTimer: Timer?
    
    private init() {}
    
    func show(volume: Float) {
        DispatchQueue.main.async {
            self.createWindowIfNeeded()
            
            if let window = self.hudWindow {
                withAnimation(.spring(duration: 0.3)) {
                    window.contentView = NSHostingView(rootView: VolumeHUD(volume: volume))
                }
                window.alphaValue = 1.0
                window.orderFront(nil)
                
                self.hideTimer?.invalidate()
                self.hideTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
                    DispatchQueue.main.async {
                        NSAnimationContext.runAnimationGroup({ context in
                            context.duration = 0.4
                            window.animator().alphaValue = 0.0
                        }, completionHandler: {
                            if window.alphaValue == 0 {
                                window.orderOut(nil)
                            }
                        })
                    }
                }
            }
        }
    }
    
    private func createWindowIfNeeded() {
        guard hudWindow == nil else { return }
        
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 160),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        
        panel.level = .mainMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.center()
        
        self.hudWindow = panel
    }
}
