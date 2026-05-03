import AppKit
import ObjectiveC

// Bridge to Apple's private OSD framework so we can render the real system
// volume HUD instead of a custom panel. Same approach used by MonitorControl,
// MediaMate, BetterDisplay. The framework moved from OSDUIHelper.framework
// to OSD.framework around macOS 14; we try the new path first and fall back
// to the old one. All calls fail closed (no HUD) if the symbols ever go away.
final class SystemVolumeHUD {
    static let shared = SystemVolumeHUD()

    private static let speakerImage: Int64 = 3
    private static let mutedImage: Int64 = 4
    private static let totalChiclets: UInt32 = 16
    private static let priority: UInt32 = 0x1F4
    private static let msecUntilFade: UInt32 = 1000

    private static let frameworkPaths = [
        "/System/Library/PrivateFrameworks/OSD.framework",
        "/System/Library/PrivateFrameworks/OSDUIHelper.framework",
    ]

    private let osdManager: NSObject?
    private let showSelector = NSSelectorFromString(
        "showImage:onDisplayID:priority:msecUntilFade:filledChiclets:totalChiclets:locked:"
    )

    // Dedupe by (chiclet count, muted) so a 60-120Hz gesture only fires an
    // OSD XPC call when the visible state actually changes. Without this the
    // HUD lags behind the gesture as redundant calls queue up in OSDUIHelper.
    private var lastFilled: UInt32 = .max
    private var lastMuted: Bool = false

    private init() {
        for path in Self.frameworkPaths {
            if let bundle = Bundle(path: path), bundle.load() { break }
        }

        guard let cls = NSClassFromString("OSDManager") else {
            print("SystemVolumeHUD: OSDManager class not found")
            self.osdManager = nil
            return
        }
        let sharedSelector = NSSelectorFromString("sharedManager")
        guard let method = class_getClassMethod(cls, sharedSelector) else {
            print("SystemVolumeHUD: +sharedManager not found")
            self.osdManager = nil
            return
        }
        typealias SharedManagerFn = @convention(c) (AnyClass, Selector) -> AnyObject?
        let getShared = unsafeBitCast(method_getImplementation(method), to: SharedManagerFn.self)
        self.osdManager = getShared(cls, sharedSelector) as? NSObject
    }

    func show(volume: Float, muted: Bool) {
        guard let osd = osdManager, osd.responds(to: showSelector) else { return }

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
        let imp = osd.method(for: showSelector)
        let show = unsafeBitCast(imp, to: ShowFn.self)
        show(osd, showSelector,
             image, CGMainDisplayID(),
             Self.priority, Self.msecUntilFade,
             filled, Self.totalChiclets,
             ObjCBool(false))
    }
}
