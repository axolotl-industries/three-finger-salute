import AppKit
import SwiftUI
import ObjectiveC

// Public façade around the volume HUD. Selects a backend at init:
//   - macOS 13–26: Apple's private OSD framework (OSDManager XPC to
//     OSDUIHelper.app). Same approach used by MonitorControl, MediaMate.
//   - macOS 27+ (Golden Gate): Apple added a Launch Environment Constraint
//     on OSDUIHelper.app; AMFI kills the helper with SIGKILL ("Launch
//     Constraint Violation") whenever a third-party process triggers its
//     launch via OSDManager XPC. The XPC call still returns silently, so
//     the HUD just never renders. Only Apple can grant the entitlement
//     that satisfies the constraint, so we fall back to a custom HUD
//     styled to match the system one.
final class SystemVolumeHUD {
    static let shared = SystemVolumeHUD()

    private let backend: HUDBackend

    private init() {
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 {
            backend = CustomHUDBackend()
        } else {
            backend = OSDBackend() ?? CustomHUDBackend()
        }
    }

    func show(volume: Float, muted: Bool) {
        backend.show(volume: volume, muted: muted)
    }
}

private protocol HUDBackend: AnyObject {
    func show(volume: Float, muted: Bool)
}

// MARK: - OSD framework backend (macOS 13–26)

private final class OSDBackend: HUDBackend {
    private static let speakerImage: Int64 = 3
    private static let mutedImage: Int64 = 4
    private static let totalChiclets: UInt32 = 16
    private static let priority: UInt32 = 0x1F4
    private static let msecUntilFade: UInt32 = 1000

    private static let frameworkPaths = [
        "/System/Library/PrivateFrameworks/OSD.framework",
        "/System/Library/PrivateFrameworks/OSDUIHelper.framework",
    ]

    private let osdManager: NSObject
    private let showSelector = NSSelectorFromString(
        "showImage:onDisplayID:priority:msecUntilFade:filledChiclets:totalChiclets:locked:"
    )

    // Dedupe by (chiclet count, muted) so a 60-120Hz gesture only fires an
    // OSD XPC call when the visible state actually changes.
    private var lastFilled: UInt32 = .max
    private var lastMuted: Bool = false

    init?() {
        for path in Self.frameworkPaths {
            if let bundle = Bundle(path: path), bundle.load() { break }
        }

        guard let cls = NSClassFromString("OSDManager") else { return nil }
        let sharedSelector = NSSelectorFromString("sharedManager")
        guard let method = class_getClassMethod(cls, sharedSelector) else { return nil }
        typealias SharedManagerFn = @convention(c) (AnyClass, Selector) -> AnyObject?
        let getShared = unsafeBitCast(method_getImplementation(method), to: SharedManagerFn.self)
        guard let mgr = getShared(cls, sharedSelector) as? NSObject,
              mgr.responds(to: showSelector) else { return nil }
        self.osdManager = mgr
    }

    func show(volume: Float, muted: Bool) {
        let level = max(0, min(1, volume))
        let image = muted ? Self.mutedImage : Self.speakerImage
        let filled = muted ? UInt32(0) : UInt32(round(level * Float(Self.totalChiclets)))

        if filled == lastFilled && muted == lastMuted { return }
        lastFilled = filled
        lastMuted = muted

        typealias ShowFn = @convention(c) (
            AnyObject, Selector,
            Int64, CGDirectDisplayID,
            UInt32, UInt32, UInt32, UInt32,
            ObjCBool
        ) -> Void
        let imp = osdManager.method(for: showSelector)
        let show = unsafeBitCast(imp, to: ShowFn.self)
        show(osdManager, showSelector,
             image, CGMainDisplayID(),
             Self.priority, Self.msecUntilFade,
             filled, Self.totalChiclets,
             ObjCBool(false))
    }
}

// MARK: - Custom HUD backend (macOS 27+)

private final class CustomHUDBackend: HUDBackend {
    private static let totalChiclets: Int = 16
    private static let visibleDuration: TimeInterval = 1.0
    private static let fadeDuration: TimeInterval = 0.25
    private static let panelSize = NSSize(width: 200, height: 200)
    private static let bottomInset: CGFloat = 140

    private var panel: HUDPanel?
    private var hostingView: NSHostingView<CustomHUDView>?
    private var hideTimer: Timer?
    private var lastFilled: Int = -1
    private var lastMuted: Bool = false

    func show(volume: Float, muted: Bool) {
        let level = max(0, min(1, volume))
        let filled = muted ? 0 : Int(round(level * Float(Self.totalChiclets)))
        DispatchQueue.main.async { [weak self] in
            self?.present(filled: filled, muted: muted)
        }
    }

    @MainActor
    private func present(filled: Int, muted: Bool) {
        ensurePanel()
        guard let panel, let hostingView else { return }

        if filled != lastFilled || muted != lastMuted {
            lastFilled = filled
            lastMuted = muted
            hostingView.rootView = CustomHUDView(
                filled: filled, total: Self.totalChiclets, muted: muted
            )
        }

        if !panel.isVisible {
            positionPanel(panel)
            panel.alphaValue = 1.0
            panel.orderFrontRegardless()
        } else if panel.alphaValue < 1.0 {
            panel.alphaValue = 1.0
        }

        scheduleHide()
    }

    @MainActor
    private func ensurePanel() {
        guard panel == nil else { return }
        let panel = HUDPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.level = .screenSaver
        panel.collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
        ]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        // System HUD is always dark, regardless of Appearance setting.
        panel.appearance = NSAppearance(named: .vibrantDark)

        let hosting = NSHostingView(
            rootView: CustomHUDView(filled: 0, total: Self.totalChiclets, muted: false)
        )
        hosting.frame = NSRect(origin: .zero, size: Self.panelSize)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        self.panel = panel
        self.hostingView = hosting
    }

    @MainActor
    private func positionPanel(_ panel: NSPanel) {
        // Menu-bar-only apps have no key window, so NSScreen.main is often
        // wrong. Pin to the screen containing the cursor (which is where
        // the user just performed a three-finger swipe).
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }
        let frame = screen.frame
        let origin = NSPoint(
            x: frame.midX - Self.panelSize.width / 2,
            y: frame.minY + Self.bottomInset
        )
        panel.setFrameOrigin(origin)
    }

    @MainActor
    private func scheduleHide() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: Self.visibleDuration, repeats: false) { [weak panel] _ in
            guard let panel else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = CustomHUDBackend.fadeDuration
                panel.animator().alphaValue = 0.0
            }, completionHandler: {
                if panel.alphaValue == 0 { panel.orderOut(nil) }
            })
        }
    }
}

// NSPanel that never becomes key or main, so activating it can't steal the
// menu bar or focus from the frontmost app.
private final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct CustomHUDView: View {
    let filled: Int
    let total: Int
    let muted: Bool

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 56, weight: .regular))
                .foregroundStyle(.white.opacity(0.9))
                .frame(height: 60)

            HStack(spacing: 3) {
                ForEach(0..<total, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(i < filled ? Color.white.opacity(0.9) : Color.white.opacity(0.18))
                }
            }
            .frame(height: 8)
            .padding(.horizontal, 22)
        }
        .frame(width: 200, height: 200)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
