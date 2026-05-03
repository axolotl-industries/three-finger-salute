import Foundation
import CoreGraphics
import AppKit

class GestureController: MultitouchDelegate {
    static let shared = GestureController()

    private var isTracking = false
    private var lastTouchUpdate = Date()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // Middle click tracking
    private var touchStartTime: Date?
    private var startY: Float = 0
    private var initialVolume: Float = 0
    private var hasMovedSignificantly = false
    private var hasPhysicallyClicked = false

    // Cached settings — refreshed on UserDefaults.didChangeNotification rather
    // than read per-frame / per-event in the hot path.
    private var isVolumeSwipeEnabled = true
    private var isMiddleClickEnabled = true
    private var swipeSensitivity: Float = 1.2

    private init() {
        loadSettings()
        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsChanged),
            name: UserDefaults.didChangeNotification, object: nil
        )
        setupEventTap()
    }

    @objc private func settingsChanged() { loadSettings() }

    private func loadSettings() {
        let d = UserDefaults.standard
        isVolumeSwipeEnabled = d.object(forKey: "isVolumeSwipeEnabled") as? Bool ?? true
        isMiddleClickEnabled = d.object(forKey: "isMiddleClickEnabled") as? Bool ?? true
        let raw = d.double(forKey: "swipeSensitivity")
        swipeSensitivity = Float(raw == 0 ? 1.2 : raw)
    }

    func start() {
        print("GestureController: Monitoring gestures...")
        MultitouchManager.shared.delegate = self
        MultitouchManager.shared.start()
    }

    func restart() {
        print("GestureController: Restarting...")
        stopEventTap()
        setupEventTap()
        MultitouchManager.shared.restart()
    }

    private func stopEventTap() {
        if let tap = eventTap {
            print("GestureController: Stopping event tap")
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }
    }

    private func setupEventTap() {
        if eventTap != nil {
            print("GestureController: Event tap already exists, skipping creation")
            return
        }

        let mask = (1 << CGEventType.scrollWheel.rawValue) |
                   (1 << CGEventType.leftMouseDown.rawValue) |
                   (1 << CGEventType.leftMouseUp.rawValue) |
                   (1 << CGEventType.tabletProximity.rawValue)

        let callback: CGEventTapCallBack = { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = GestureController.shared.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passRetained(event)
            }

            let g = GestureController.shared

            // Watchdog: if 3-finger state went stale (>150ms since last touch
            // frame), bail out so we stop swallowing events.
            if g.isTracking && Date().timeIntervalSince(g.lastTouchUpdate) > 0.15 {
                print("GESTURE: Watchdog reset isTracking (stale touches)")
                g.isTracking = false
                MultitouchManager.shared.setExclusiveMode(false)
            }

            if g.isTracking {
                if type == .scrollWheel {
                    return nil
                }

                if type == .leftMouseDown || type == .leftMouseUp {
                    g.hasPhysicallyClicked = true

                    if !g.isMiddleClickEnabled {
                        return Unmanaged.passRetained(event)
                    }

                    let mouseEvent = CGEvent(
                        mouseEventSource: nil,
                        mouseType: type == .leftMouseDown ? .otherMouseDown : .otherMouseUp,
                        mouseCursorPosition: event.location,
                        mouseButton: .center
                    )
                    mouseEvent?.setIntegerValueField(.mouseEventClickState, value: 1)
                    return mouseEvent.map { Unmanaged.passRetained($0) }
                }
            }
            return Unmanaged.passRetained(event)
        }

        eventTap = CGEvent.tapCreate(tap: .cghidEventTap,
                                   place: .headInsertEventTap,
                                   options: .defaultTap,
                                   eventsOfInterest: CGEventMask(mask),
                                   callback: callback,
                                   userInfo: nil)

        if let tap = eventTap {
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            self.runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    private func calculateMaxDistance(_ touches: [MTContact]) -> Float {
        var maxD: Float = 0
        for i in 0..<touches.count {
            for j in i+1..<touches.count {
                let dx = touches[i].normalizedX - touches[j].normalizedX
                let dy = touches[i].normalizedY - touches[j].normalizedY
                let dist = sqrt(dx*dx + dy*dy)
                if dist > maxD { maxD = dist }
            }
        }
        return maxD
    }

    func didUpdateTouches(_ touches: [MTContact]) {
        lastTouchUpdate = Date()
        let activeTouches = touches.filter { $0.state == 4 }

        if activeTouches.count == 3 {
            // Palm rejection: 3-finger gestures should be relatively bunched together.
            let maxDist = calculateMaxDistance(activeTouches)
            if maxDist > 0.5 {
                if !isTracking { return }
            }

            let averageY = activeTouches.reduce(0) { $0 + $1.normalizedY } / Float(activeTouches.count)

            if !isTracking {
                isTracking = true
                MultitouchManager.shared.setExclusiveMode(true)
                touchStartTime = Date()
                startY = averageY
                initialVolume = VolumeManager.shared.getVolume()
                hasMovedSignificantly = false
                hasPhysicallyClicked = false
                print("GESTURE: 3 Fingers Down (maxDist: \(maxDist))")
            }

            let deltaY = averageY - startY
            if abs(deltaY) > 0.05 {
                hasMovedSignificantly = true
            }

            if hasMovedSignificantly && isVolumeSwipeEnabled {
                let newVolume = initialVolume + (deltaY * swipeSensitivity)
                VolumeManager.shared.setVolume(newVolume)
            }

        } else if activeTouches.count == 0 {
            if isTracking || touchStartTime != nil {
                if !hasPhysicallyClicked,
                   isMiddleClickEnabled,
                   let startTime = touchStartTime,
                   Date().timeIntervalSince(startTime) < 0.25,
                   !hasMovedSignificantly {
                    triggerMiddleClick()
                }
                print("GESTURE: All Fingers Up")
            }

            isTracking = false
            MultitouchManager.shared.setExclusiveMode(false)
            touchStartTime = nil

        } else {
            if isTracking {
                print("GESTURE: 3 Fingers reduced to \(activeTouches.count) (Graceful transition)")
                isTracking = false
                MultitouchManager.shared.setExclusiveMode(false)
            }

            if let startTime = touchStartTime {
                if Date().timeIntervalSince(startTime) > 0.3 {
                    touchStartTime = nil
                }
            }
        }
    }

    private func triggerMiddleClick() {
        print("GESTURE: Triggering Middle Click (Tap)")
        guard let dummyEvent = CGEvent(source: nil) else { return }
        let currentPos = dummyEvent.location

        let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .otherMouseDown, mouseCursorPosition: currentPos, mouseButton: .center)
        let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .otherMouseUp, mouseCursorPosition: currentPos, mouseButton: .center)

        mouseDown?.setIntegerValueField(.mouseEventClickState, value: 1)
        mouseUp?.setIntegerValueField(.mouseEventClickState, value: 1)

        mouseDown?.post(tap: .cghidEventTap)
        mouseUp?.post(tap: .cghidEventTap)
    }
}
