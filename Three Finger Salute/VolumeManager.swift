import Foundation
import CoreAudio
import AudioToolbox
import AppKit

final class VolumeManager {
    static let shared = VolumeManager()

    var onChange: ((Float, Bool) -> Void)?

    private var deviceID: AudioDeviceID = kAudioObjectUnknown
    private var volumeAddress = AudioObjectPropertyAddress()
    private var muteAddress = AudioObjectPropertyAddress()
    private var lastShownVolume: Float = -1
    private var lastShownMuted: Bool = false

    private var defaultDeviceListener: AudioObjectPropertyListenerBlock?
    private var deviceVolumeListener: AudioObjectPropertyListenerBlock?
    private var deviceMuteListener: AudioObjectPropertyListenerBlock?

    private init() {
        refreshDevice()
        installDefaultDeviceListener()
    }

    func getVolume() -> Float {
        guard deviceID != kAudioObjectUnknown else { return 0.5 }
        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var addr = volumeAddress
        let status = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &volume)
        return status == noErr ? Float(volume) : 0.5
    }

    func isMuted() -> Bool {
        guard deviceID != kAudioObjectUnknown else { return false }
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var addr = muteAddress
        let status = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &muted)
        return status == noErr && muted != 0
    }

    func setVolume(_ volume: Float) {
        guard deviceID != kAudioObjectUnknown else { return }

        let clamped = max(0, min(1, volume))
        var newVolume = Float32(clamped)
        let floatSize = UInt32(MemoryLayout<Float32>.size)
        var addr = volumeAddress
        AudioObjectSetPropertyData(deviceID, &addr, 0, nil, floatSize, &newVolume)

        if addr.mElement == 1 {
            var ch2 = addr
            ch2.mElement = 2
            if AudioObjectHasProperty(deviceID, &ch2) {
                AudioObjectSetPropertyData(deviceID, &ch2, 0, nil, floatSize, &newVolume)
            }
        }

        // Mute at zero, unmute above. Otherwise the system treats vol=0 and
        // muted as different states (different HUD icon, different menu icon).
        var muteFlag: UInt32 = clamped > 0 ? 0 : 1
        var mAddr = muteAddress
        AudioObjectSetPropertyData(deviceID, &mAddr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &muteFlag)

        notifyIfChanged(volume: clamped, muted: muteFlag != 0, fromUs: true)
    }

    private func notifyIfChanged(volume: Float, muted: Bool, fromUs: Bool) {
        if abs(volume - lastShownVolume) < 0.001 && muted == lastShownMuted { return }
        lastShownVolume = volume
        lastShownMuted = muted
        if fromUs {
            SystemVolumeHUD.shared.show(volume: volume, muted: muted)
        }
        onChange?(volume, muted)
    }

    private func refreshDevice() {
        removeDeviceListeners()

        var newID = kAudioObjectUnknown
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &newID
        )
        guard status == noErr, newID != kAudioObjectUnknown else {
            deviceID = kAudioObjectUnknown
            return
        }

        deviceID = newID
        volumeAddress = computeVolumeAddress(for: newID)
        muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        installDeviceListeners()
    }

    private func computeVolumeAddress(for device: AudioDeviceID) -> AudioObjectPropertyAddress {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(device, &address) { return address }
        address.mElement = 1
        if AudioObjectHasProperty(device, &address) { return address }
        address.mElement = kAudioObjectPropertyElementMain
        return address
    }

    private func installDefaultDeviceListener() {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { self?.refreshDevice() }
        }
        defaultDeviceListener = block
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main, block
        )
    }

    private func installDeviceListeners() {
        guard deviceID != kAudioObjectUnknown else { return }

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            DispatchQueue.main.async {
                self.notifyIfChanged(
                    volume: self.getVolume(), muted: self.isMuted(), fromUs: false
                )
            }
        }

        var vAddr = volumeAddress
        AudioObjectAddPropertyListenerBlock(deviceID, &vAddr, DispatchQueue.main, block)
        deviceVolumeListener = block

        var mAddr = muteAddress
        AudioObjectAddPropertyListenerBlock(deviceID, &mAddr, DispatchQueue.main, block)
        deviceMuteListener = block
    }

    private func removeDeviceListeners() {
        guard deviceID != kAudioObjectUnknown else { return }
        if let v = deviceVolumeListener {
            var addr = volumeAddress
            AudioObjectRemovePropertyListenerBlock(deviceID, &addr, DispatchQueue.main, v)
            deviceVolumeListener = nil
        }
        if let m = deviceMuteListener {
            var addr = muteAddress
            AudioObjectRemovePropertyListenerBlock(deviceID, &addr, DispatchQueue.main, m)
            deviceMuteListener = nil
        }
    }
}
