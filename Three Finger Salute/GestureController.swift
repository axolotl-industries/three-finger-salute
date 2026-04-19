import Foundation
import CoreGraphics
import AppKit

class GestureController: MultitouchDelegate {
    static let shared = GestureController()
    
    private var isTracking = false
    private var lastTouchUpdate = Date()
    private var eventTap: CFMachPort?
    
    // Middle click tracking
    private var touchStartTime: Date?
    private var startY: Float = 0
    private var initialVolume: Float = 0
    private var hasMovedSignificantly = false
    private var hasPhysicallyClicked = false
    
    private init() {
        setupEventTap()
    }
    
    func start() {
        print("GestureController: Monitoring gestures...")
        MultitouchManager.shared.delegate = self
        MultitouchManager.shared.start()
    }

    func restart() {
        print("GestureController: Restarting...")
        if let tap = eventTap {
            if !CGEvent.tapIsEnabled(tap: tap) {
                print("GestureController: Re-enabling existing tap")
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        } else {
            setupEventTap()
        }
        MultitouchManager.shared.restart()
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
            // If the system disabled our tap, we might need to handle it here too
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = GestureController.shared.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passRetained(event)
            }

            // Safety watchdog: if we haven't received a touch update in 150ms, 
            // the fingers are likely gone or the framework is stuck.
            if GestureController.shared.isTracking && Date().timeIntervalSince(GestureController.shared.lastTouchUpdate) > 0.15 {
                print("GESTURE: Watchdog reset isTracking (stale touches)")
                GestureController.shared.isTracking = false
            }

            // If we have 3 fingers on the trackpad, we take control of all clicks
            if GestureController.shared.isTracking {

                if type == .scrollWheel {
                    return nil // Block scrolling
                }
                
                if type == .leftMouseDown || type == .leftMouseUp {
                    GestureController.shared.hasPhysicallyClicked = true

                    let isMiddleClickEnabled = UserDefaults.standard.object(forKey: "isMiddleClickEnabled") == nil ? true : UserDefaults.standard.bool(forKey: "isMiddleClickEnabled")

                    if !isMiddleClickEnabled {
                        return Unmanaged.passRetained(event)
                    }

                    // Convert physical 3-finger click to Middle Click (Button 2)

                    let mouseEvent = CGEvent(mouseEventSource: nil, 
                                           mouseType: type == .leftMouseDown ? .otherMouseDown : .otherMouseUp, 
                                           mouseCursorPosition: event.location, 
                                           mouseButton: .center)
                    
                    // Ensure it's marked as a single click to prevent "double click" weirdness
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
            let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }
    
    private func calculateMaxDistance(_ touches: [MTContact]) -> Float {
        var maxD: Float = 0
        for i in 0..<touches.count {
            for j in i+1..<touches.count {
                let dx = touches[i].viewX - touches[j].viewX
                let dy = touches[i].viewY - touches[j].viewY
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
            // A typical 3-finger cluster is usually < 0.4 of trackpad width.
            // We'll use 0.5 to be safe and avoid blocking legitimate taps.
            let maxDist = calculateMaxDistance(activeTouches)
            if maxDist > 0.5 {
                // If we were already tracking, we can continue, but don't start a NEW track
                // if the fingers are too spread out (likely a palm + 2 fingers).
                if !isTracking { return }
            }

            let averageY = activeTouches.reduce(0) { $0 + $1.viewY } / Float(activeTouches.count)
            
            if !isTracking {
                isTracking = true
                touchStartTime = Date()
                startY = averageY
                initialVolume = VolumeManager.shared.getVolume()
                hasMovedSignificantly = false
                hasPhysicallyClicked = false
                print("GESTURE: 3 Fingers Down (maxDist: \(maxDist))")
            }
            
            let deltaY = averageY - startY
            if abs(deltaY) > 0.05 { // Restored to 0.05 to prevent accidental swipe detection during tap
                hasMovedSignificantly = true
            }

            let isVolumeEnabled = UserDefaults.standard.object(forKey: "isVolumeSwipeEnabled") == nil ? true : UserDefaults.standard.bool(forKey: "isVolumeSwipeEnabled")

            if hasMovedSignificantly && isVolumeEnabled {
                // Sensitivity: how much trackpad movement equals full volume range.
                let userSensitivity = UserDefaults.standard.double(forKey: "swipeSensitivity")
                let sensitivity = Float(userSensitivity == 0 ? 1.2 : userSensitivity)
                let newVolume = initialVolume + (deltaY * sensitivity)
                VolumeManager.shared.setVolume(newVolume)
            }

        } else if isTracking {
            // Reset tracking whenever count is not exactly 3.
            
            // Check for middle click tap only when count drops to 0.
            if activeTouches.count == 0 {
                let isMiddleClickEnabled = UserDefaults.standard.object(forKey: "isMiddleClickEnabled") == nil ? true : UserDefaults.standard.bool(forKey: "isMiddleClickEnabled")

                // Trigger tap-middle-click ONLY if we haven't already physically clicked
                if !hasPhysicallyClicked,
                   isMiddleClickEnabled,
                   let startTime = touchStartTime, 
                   Date().timeIntervalSince(startTime) < 0.25, 
                   !hasMovedSignificantly {
                    triggerMiddleClick()
                }
                print("GESTURE: 3 Fingers Up (Clean)")
            } else {
                print("GESTURE: 3 Fingers Interrupted (count: \(activeTouches.count))")
            }
            
            isTracking = false
            touchStartTime = nil
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
