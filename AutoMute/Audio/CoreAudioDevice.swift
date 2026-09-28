import CoreAudio
import Foundation

enum CoreAudioDevice {
    static let defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    static let devicesAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    private static let silentVolumeThreshold: Float32 = 0.01

    static func defaultOutputDeviceID() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = defaultOutputAddress
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else {
            return nil
        }
        return deviceID
    }

    static func allOutputDeviceIDs() -> [AudioDeviceID] {
        var address = devicesAddress
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        ) == noErr else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceIDs
        ) == noErr else {
            return []
        }

        return deviceIDs.filter { hasOutputChannels($0) }
    }

    static func nonBluetoothOutputDeviceIDs() -> [AudioDeviceID] {
        allOutputDeviceIDs().filter { !isBluetooth($0) }
    }

    static func name(of deviceID: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfName: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &cfName) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let cfName else {
            return "Unknown"
        }
        return cfName.takeRetainedValue() as String
    }

    static func transportType(of deviceID: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &transport)
        guard status == noErr else {
            return 0
        }
        return transport
    }

    static func isBluetooth(_ deviceID: AudioDeviceID) -> Bool {
        let transport = transportType(of: deviceID)
        return transport == kAudioDeviceTransportTypeBluetooth
            || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    @discardableResult
    static func setMuted(_ muted: Bool, deviceID: AudioDeviceID) -> Bool {
        if setMuteProperty(muted, deviceID: deviceID) {
            return true
        }
        // Some devices do not support mute; fall back to volume scalar.
        if muted {
            return setVolumeScalar(0, deviceID: deviceID)
        }
        // Unmute via volume: restore a reasonable level if currently near silent.
        let current = volumeScalar(of: deviceID) ?? 0
        if current < silentVolumeThreshold {
            return setVolumeScalar(0.5, deviceID: deviceID)
        }
        return true
    }

    static func isMuted(_ deviceID: AudioDeviceID) -> Bool {
        var address = muteAddress()
        guard AudioObjectHasProperty(deviceID, &address) else {
            return (volumeScalar(of: deviceID) ?? 1) < silentVolumeThreshold
        }
        var mute: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &mute)
        return status == noErr && mute != 0
    }

    // MARK: - Private

    private static func hasOutputChannels(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr,
              dataSize > 0 else {
            return false
        }

        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, raw) == noErr else {
            return false
        }

        let bufferList = raw.assumingMemoryBound(to: AudioBufferList.self)
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
    }

    private static func muteAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func setMuteProperty(_ muted: Bool, deviceID: AudioDeviceID) -> Bool {
        var address = muteAddress()
        guard AudioObjectHasProperty(deviceID, &address),
              isPropertySettable(deviceID, &address) else {
            return false
        }

        var mute: UInt32 = muted ? 1 : 0
        let status = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &mute
        )
        return status == noErr
    }

    private static func isPropertySettable(
        _ deviceID: AudioDeviceID,
        _ address: inout AudioObjectPropertyAddress
    ) -> Bool {
        var settable: DarwinBoolean = false
        let status = AudioObjectIsPropertySettable(deviceID, &address, &settable)
        return status == noErr && settable.boolValue
    }

    private static func volumeAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func volumeScalar(of deviceID: AudioDeviceID) -> Float32? {
        var address = volumeAddress()
        guard AudioObjectHasProperty(deviceID, &address) else {
            return nil
        }
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
        guard status == noErr else {
            return nil
        }
        return volume
    }

    private static func setVolumeScalar(_ volume: Float32, deviceID: AudioDeviceID) -> Bool {
        var address = volumeAddress()
        guard AudioObjectHasProperty(deviceID, &address),
              isPropertySettable(deviceID, &address) else {
            return setPerChannelVolume(volume, deviceID: deviceID)
        }
        var value = volume
        let status = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<Float32>.size),
            &value
        )
        return status == noErr
    }

    private static func setPerChannelVolume(_ volume: Float32, deviceID: AudioDeviceID) -> Bool {
        var success = false
        for channel: UInt32 in 1...2 {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: channel
            )
            guard AudioObjectHasProperty(deviceID, &address) else {
                continue
            }
            var value = volume
            let status = AudioObjectSetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                UInt32(MemoryLayout<Float32>.size),
                &value
            )
            if status == noErr {
                success = true
            }
        }
        return success
    }
}
