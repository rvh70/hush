import CoreAudio
import Foundation

/// Reports which processes are capturing audio input, using the per-process
/// CoreAudio objects (macOS 14+). Unlike a device's "running somewhere" flag,
/// this is not fooled by music playing through a headset that also has a mic.
enum MicMonitor {
    /// Bundle IDs that hold the mic in the background and should not count.
    static let ignored: Set<String> = [
        // "Hey Siri" listening on the built-in mic.
        "com.apple.CoreSpeech",
        "com.apple.corespeechd",
        "com.apple.SpeechRecognitionCore.speechrecognitiond",
    ]

    private static var watchedProcesses: Set<AudioObjectID> = []
    private static var watchedDevices: Set<AudioObjectID> = []
    private static var onChange: (() -> Void)?

    /// Calls `handler` on the main queue whenever recording may have started
    /// or stopped. Listens both per
    /// process and per device: the per-process notifications don't fire for
    /// every app, while a device starting or stopping always fires.
    static func observe(_ handler: @escaping () -> Void) {
        onChange = handler
        let system = AudioObjectID(kAudioObjectSystemObject)
        var processes = address(kAudioHardwarePropertyProcessObjectList)
        AudioObjectAddPropertyListenerBlock(system, &processes, .main) { _, _ in
            watchNewObjects()
            onChange?()
        }
        var devices = address(kAudioHardwarePropertyDevices)
        AudioObjectAddPropertyListenerBlock(system, &devices, .main) { _, _ in
            watchNewObjects()
            onChange?()
        }
        watchNewObjects()
    }

    private static func watchNewObjects() {
        let processes = Set(objectList(kAudioHardwarePropertyProcessObjectList))
        for id in processes.subtracting(watchedProcesses) {
            var addr = address(kAudioProcessPropertyIsRunningInput)
            AudioObjectAddPropertyListenerBlock(id, &addr, .main) { _, _ in onChange?() }
        }
        let devices = Set(objectList(kAudioHardwarePropertyDevices))
        for id in devices.subtracting(watchedDevices) {
            var addr = address(kAudioDevicePropertyDeviceIsRunningSomewhere)
            AudioObjectAddPropertyListenerBlock(id, &addr, .main) { _, _ in onChange?() }
        }
        // Listeners on vanished objects die with them.
        watchedProcesses = processes
        watchedDevices = devices
    }

    /// Bundle IDs (or process names) of everything currently recording.
    static func activeInputClients() -> [String] {
        objectList(kAudioHardwarePropertyProcessObjectList).compactMap { id -> String? in
            guard boolProperty(id, kAudioProcessPropertyIsRunningInput) else { return nil }
            let name = bundleID(id) ?? "pid \(pid(id))"
            return ignored.contains(name) ? nil : name
        }
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func objectList(_ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var addr = address(selector)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func boolProperty(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Bool {
        var addr = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr && value != 0
    }

    private static func bundleID(_ id: AudioObjectID) -> String? {
        var addr = address(kAudioProcessPropertyBundleID)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr,
              let string = value?.takeRetainedValue() as String?, !string.isEmpty else { return nil }
        return string
    }

    private static func pid(_ id: AudioObjectID) -> pid_t {
        var addr = address(kAudioProcessPropertyPID)
        var value: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value)
        return value
    }
}
