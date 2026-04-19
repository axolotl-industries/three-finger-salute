import Foundation
import CoreAudio
import AudioToolbox
import AppKit

class VolumeManager {
    static let shared = VolumeManager()
    private var lastVolume: Float = -1
    
    private init() {}
    
    private func getDefaultOutputDevice() -> AudioDeviceID? {
        var deviceID = kAudioObjectUnknown
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &propertySize, &deviceID)
        return status == noErr ? deviceID : nil
    }
    
    private func getVolumeAddress(for deviceID: AudioDeviceID) -> AudioObjectPropertyAddress {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        if AudioObjectHasProperty(deviceID, &address) {
            return address
        }
        
        // If Main element is not supported, try channel 1
        address.mElement = 1
        if AudioObjectHasProperty(deviceID, &address) {
            return address
        }
        
        // Fallback to Main if nothing else works
        address.mElement = kAudioObjectPropertyElementMain
        return address
    }
    
    func getVolume() -> Float {
        guard let deviceID = getDefaultOutputDevice() else { return 0.5 }
        var volume = Float32(0.0)
        var propertySize = UInt32(MemoryLayout<Float32>.size)
        var propertyAddress = getVolumeAddress(for: deviceID)
        
        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, &volume)
        return status == noErr ? Float(volume) : 0.5
    }
    
    func setVolume(_ volume: Float) {
        guard let deviceID = getDefaultOutputDevice() else { return }
        
        let clippedVolume = max(0.0, min(1.0, volume))
        var newVolume = Float32(clippedVolume)
        let propertySize = UInt32(MemoryLayout<Float32>.size)
        
        var propertyAddress = getVolumeAddress(for: deviceID)
        
        // 1. Set the volume via CoreAudio
        AudioObjectSetPropertyData(deviceID, &propertyAddress, 0, nil, propertySize, &newVolume)
        
        // If we are setting channel 1, also try to set channel 2 to keep them in sync
        if propertyAddress.mElement == 1 {
            var chan2Address = propertyAddress
            chan2Address.mElement = 2
            if AudioObjectHasProperty(deviceID, &chan2Address) {
                AudioObjectSetPropertyData(deviceID, &chan2Address, 0, nil, propertySize, &newVolume)
            }
        }
        
        // 2. Handle Muting
        if clippedVolume > 0 {
            var mute: UInt32 = 0
            var muteAddress = propertyAddress
            muteAddress.mSelector = kAudioDevicePropertyMute
            AudioObjectSetPropertyData(deviceID, &muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &mute)
        }
        
        // 3. Show Custom HUD and post notification
        if abs(clippedVolume - lastVolume) > 0.001 {
            HUDManager.shared.show(volume: clippedVolume)
            NotificationCenter.default.post(name: NSNotification.Name("VolumeChanged"), object: clippedVolume)
            lastVolume = clippedVolume
        }

    }
}
