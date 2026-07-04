import CoreAudio

/// Native CoreAudio replacement for the sliver of ISSoundAdditions we used:
/// read/write scalar volume and mute on the system default output device.
/// All calls are best-effort — CoreAudio failures are swallowed, never crash.
enum SystemVolume {
    static func increase(by delta: Float) {
        guard let device = defaultOutputDevice() else { return }
        setVolume(device, clamp((readVolume(device) ?? 0) + delta))
        setMuted(false) // autoMuteUnmute: raising volume ensures unmuted
    }

    static func decrease(by delta: Float) {
        guard let device = defaultOutputDevice() else { return }
        let next = clamp((readVolume(device) ?? 0) - delta)
        setVolume(device, next)
        if next <= 0.0001 { setMuted(true) } // autoMuteUnmute: hit zero -> mute
    }

    /// value in 0.0...1.0
    static func setScalar(_ value: Float) {
        guard let device = defaultOutputDevice() else { return }
        let clamped = clamp(value)
        setVolume(device, clamped)
        setMuted(clamped <= 0.0001) // autoMuteUnmute: >0 unmute, 0 mute
    }

    static var isMuted: Bool {
        guard let device = defaultOutputDevice() else { return false }
        var address = muteAddress()
        guard AudioObjectHasProperty(device, &address) else { return false }
        var muted = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted)
        return status == noErr && muted != 0
    }

    static func setMuted(_ muted: Bool) {
        guard let device = defaultOutputDevice() else { return }
        var address = muteAddress()
        guard AudioObjectHasProperty(device, &address) else { return }
        var value = UInt32(muted ? 1 : 0)
        _ = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    static func toggleMuted() { setMuted(!isMuted) }

    // MARK: - CoreAudio plumbing

    private static func clamp(_ v: Float) -> Float { min(max(v, 0), 1) }

    private static func defaultOutputDevice() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    private static func muteAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func volumeAddress(element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
    }

    // ponytail: assume master volume lives on the main element; only if the device
    // doesn't expose it there do we fall back to per-channel (1 = left, 2 = right).
    // Covers the common built-in/aggregate device split without probing every channel.
    private static func readVolume(_ device: AudioObjectID) -> Float? {
        for element in [kAudioObjectPropertyElementMain, AudioObjectPropertyElement(1)] {
            var address = volumeAddress(element: element)
            guard AudioObjectHasProperty(device, &address) else { continue }
            var vol = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &vol) == noErr {
                return vol
            }
        }
        return nil
    }

    private static func setVolume(_ device: AudioObjectID, _ value: Float) {
        var mainAddress = volumeAddress(element: kAudioObjectPropertyElementMain)
        if AudioObjectHasProperty(device, &mainAddress) {
            var v = Float32(value)
            _ = AudioObjectSetPropertyData(device, &mainAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
            return
        }
        for channel in [AudioObjectPropertyElement(1), AudioObjectPropertyElement(2)] {
            var address = volumeAddress(element: channel)
            guard AudioObjectHasProperty(device, &address) else { continue }
            var v = Float32(value)
            _ = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
        }
    }
}
