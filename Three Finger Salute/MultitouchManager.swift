import Foundation
import ApplicationServices

/// Exact memory map for your Mac's trackpad (96-byte stride)
struct MTContact {
    var frame: Int32        // 0
    var reserved: Int32     // 4
    var timestamp: Double   // 8
    var identifier: Int32   // 16
    var state: Int32        // 20
    var unknown1: Int32     // 24
    var unknown2: Int32     // 28
    var viewX: Float        // 32
    var viewY: Float        // 36
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
        guard !isStarted, let register = mtRegisterContactFrameCallback, let start = mtDeviceStart else { return }

        var deviceList: [UnsafeMutableRawPointer] = []

        // Try to get all devices (Internal + Magic Trackpad)
        if let mtList = mtDeviceCreateList?() {
            let count = CFArrayGetCount(mtList)
            for i in 0..<count {
                if let dev = CFArrayGetValueAtIndex(mtList, i) {
                    deviceList.append(UnsafeMutableRawPointer(mutating: dev))
                }
            }
        }


        // Fallback to default if list is empty
        if deviceList.isEmpty, let dev = mtDeviceCreateDefault?() {
            deviceList.append(dev)
        }

        guard !deviceList.isEmpty else {
            print("MultitouchManager: No multitouch devices found")
            return
        }

        self.devices = deviceList

        for dev in devices {
            register(dev) { (device, touchesPtr, numTouches, timestamp, frame) -> Int32 in
                if let touchesPtr = touchesPtr {
                    let stride = 96 // Confirmed from DISCOVERY logs
                    var touches: [MTContact] = []

                    for i in 0..<Int(numTouches) {
                        let ptr = touchesPtr.advanced(by: i * stride)
                        let contact = ptr.assumingMemoryBound(to: MTContact.self).pointee
                        touches.append(contact)
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
        print("MultitouchManager: Active with \(devices.count) device(s)")
    }

    
    func stop() {
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
