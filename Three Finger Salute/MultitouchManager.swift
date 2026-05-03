import Foundation
import ApplicationServices

// Mirrors the private MTTouch struct from MultitouchSupport.framework. The
// 96-byte stride matches the historic layout used across recent macOS
// versions; defining all fields means MemoryLayout<MTContact>.stride stays in
// sync if we ever need to extend the struct.
struct MTContact {
    var frame: Int32
    var timestamp: Double
    var identifier: Int32
    var state: Int32
    var fingerID: Int32
    var handID: Int32
    var normalizedX: Float
    var normalizedY: Float
    var normalizedVelX: Float
    var normalizedVelY: Float
    var size: Float
    var unknown1: Int32
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var absoluteX: Float
    var absoluteY: Float
    var absoluteVelX: Float
    var absoluteVelY: Float
    var unknown2: Int32
    var unknown3: Int32
    var density: Float
}

typealias MTContactCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
typealias MTDeviceCreateDefaultFunc = @convention(c) () -> UnsafeMutableRawPointer?
typealias MTDeviceCreateListFunc = @convention(c) () -> CFArray?
typealias MTRegisterContactFrameCallbackFunc = @convention(c) (UnsafeMutableRawPointer, MTContactCallback) -> Void
typealias MTDeviceStartFunc = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
typealias MTDeviceStopFunc = @convention(c) (UnsafeMutableRawPointer) -> Void
typealias MTDeviceSetPropertyFunc = @convention(c) (UnsafeMutableRawPointer, Int32, CFTypeRef) -> Void

protocol MultitouchDelegate: AnyObject {
    func didUpdateTouches(_ touches: [MTContact])
}

class MultitouchManager {
    static let shared = MultitouchManager()
    weak var delegate: MultitouchDelegate?
    private var devices: [UnsafeMutableRawPointer] = []
    private var isStarted = false

    private var mtDeviceCreateDefault: MTDeviceCreateDefaultFunc?
    private var mtDeviceCreateList: MTDeviceCreateListFunc?
    private var mtRegisterContactFrameCallback: MTRegisterContactFrameCallbackFunc?
    private var mtDeviceStart: MTDeviceStartFunc?
    private var mtDeviceStop: MTDeviceStopFunc?
    private var mtDeviceSetProperty: MTDeviceSetPropertyFunc?

    private var isSearching = false

    private init() {
        loadFramework()
    }

    private func loadFramework() {
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let handle = dlopen(path, RTLD_NOW) else { return }
        mtDeviceCreateDefault = unsafeBitCast(dlsym(handle, "MTDeviceCreateDefault"), to: MTDeviceCreateDefaultFunc?.self)
        mtDeviceCreateList = unsafeBitCast(dlsym(handle, "MTDeviceCreateList"), to: MTDeviceCreateListFunc?.self)
        mtRegisterContactFrameCallback = unsafeBitCast(dlsym(handle, "MTRegisterContactFrameCallback"), to: MTRegisterContactFrameCallbackFunc?.self)
        mtDeviceStart = unsafeBitCast(dlsym(handle, "MTDeviceStart"), to: MTDeviceStartFunc?.self)
        mtDeviceStop = unsafeBitCast(dlsym(handle, "MTDeviceStop"), to: MTDeviceStopFunc?.self)
        mtDeviceSetProperty = unsafeBitCast(dlsym(handle, "MTDeviceSetProperty"), to: MTDeviceSetPropertyFunc?.self)
    }

    func start() {
        if isStarted || isSearching { return }
        isSearching = true
        start(retryCount: 0)
    }

    private func start(retryCount: Int) {
        guard isSearching && !isStarted, let register = mtRegisterContactFrameCallback, let start = mtDeviceStart else { return }

        var deviceList: [UnsafeMutableRawPointer] = []

        if let mtList = mtDeviceCreateList?() {
            let count = CFArrayGetCount(mtList)
            for i in 0..<count {
                if let dev = CFArrayGetValueAtIndex(mtList, i) {
                    deviceList.append(UnsafeMutableRawPointer(mutating: dev))
                }
            }
        }

        if deviceList.isEmpty, let dev = mtDeviceCreateDefault?() {
            deviceList.append(dev)
        }

        guard !deviceList.isEmpty else {
            print("MultitouchManager: No multitouch devices found (retry: \(retryCount))")
            if retryCount < 5 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.start(retryCount: retryCount + 1)
                }
            } else {
                isSearching = false
            }
            return
        }

        self.devices = deviceList

        for dev in devices {
            register(dev) { (device, touchesPtr, numTouches, timestamp, frame) -> Int32 in
                if let touchesPtr = touchesPtr {
                    let stride = MemoryLayout<MTContact>.stride
                    var touches: [MTContact] = []
                    touches.reserveCapacity(Int(numTouches))
                    for i in 0..<Int(numTouches) {
                        let ptr = touchesPtr.advanced(by: i * stride)
                        touches.append(ptr.assumingMemoryBound(to: MTContact.self).pointee)
                    }
                    DispatchQueue.main.async {
                        MultitouchManager.shared.delegate?.didUpdateTouches(touches)
                    }
                }
                return 0
            }
            start(dev, 0)
        }

        isStarted = true
        isSearching = false
        print("MultitouchManager: Active with \(devices.count) device(s), stride=\(MemoryLayout<MTContact>.stride)")
    }


    func stop() {
        isSearching = false
        guard isStarted, let stop = mtDeviceStop else { return }
        for dev in devices {
            stop(dev)
        }
        devices.removeAll()
        isStarted = false
    }

    func restart() {
        print("MultitouchManager: Restarting...")
        stop()
        start()
    }

    func setExclusiveMode(_ enabled: Bool) {
        guard let setProperty = mtDeviceSetProperty else { return }
        let value = enabled ? kCFBooleanTrue : kCFBooleanFalse
        for dev in devices {
            setProperty(dev, 142, value!)
        }
        print("MultitouchManager: Exclusive mode \(enabled ? "enabled" : "disabled")")
    }
}
