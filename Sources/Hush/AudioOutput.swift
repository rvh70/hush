import CoreAudio

enum AudioOutput {
    /// Nominal sample rate of the default output device, or 0 if unknown.
    /// AirPods drop to 16–24 kHz while their mic is in use.
    static func sampleRate() -> Double {
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device) == noErr
        else { return 0 }

        var rate: Float64 = 0
        size = UInt32(MemoryLayout<Float64>.size)
        addr.mSelector = kAudioDevicePropertyNominalSampleRate
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &rate) == noErr else { return 0 }
        return rate
    }
}
