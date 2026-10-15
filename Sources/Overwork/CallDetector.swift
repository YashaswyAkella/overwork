import CoreAudio
import CoreMediaIO
import Foundation

/// Detects an ongoing call: some other process is capturing the microphone, or any camera is running.
enum CallDetector {
    struct Report {
        var micUsers: [String]
        var cameraRunning: Bool
        var audioClients: [String]   // every process CoreAudio knows about, for diagnostics
        var inCall: Bool { !micUsers.isEmpty || cameraRunning }
    }

    static func inCall() -> Bool { !processesCapturingInput().isEmpty || cameraInUse() }

    static func report() -> Report {
        Report(micUsers: processesCapturingInput(), cameraRunning: cameraInUse(), audioClients: audioClientNames())
    }

    private static func audioClientNames() -> [String] {
        guard #available(macOS 14.2, *) else { return [] }
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &objects) == noErr else { return [] }
        return objects.map { obj in
            var bundle: Unmanaged<CFString>? = nil
            var bsize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var baddr = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID,
                                                   mScope: kAudioObjectPropertyScopeGlobal,
                                                   mElement: kAudioObjectPropertyElementMain)
            _ = AudioObjectGetPropertyData(obj, &baddr, 0, nil, &bsize, &bundle)
            return bundle.map { $0.takeRetainedValue() as String } ?? "?"
        }
    }

    // MARK: Microphone (per-process audio objects, macOS 14.2+)

    private static func processesCapturingInput() -> [String] {
        guard #available(macOS 14.2, *) else { return micInUseAnyDevice() ? ["unknown"] : [] }
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &objects) == noErr else { return [] }

        var users: [String] = []
        for obj in objects {
            var running: UInt32 = 0
            var rsize = UInt32(MemoryLayout<UInt32>.size)
            var raddr = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunningInput,
                                                   mScope: kAudioObjectPropertyScopeGlobal,
                                                   mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectGetPropertyData(obj, &raddr, 0, nil, &rsize, &running) == noErr, running != 0 else { continue }

            var pid: pid_t = 0
            var psize = UInt32(MemoryLayout<pid_t>.size)
            var paddr = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyPID,
                                                   mScope: kAudioObjectPropertyScopeGlobal,
                                                   mElement: kAudioObjectPropertyElementMain)
            _ = AudioObjectGetPropertyData(obj, &paddr, 0, nil, &psize, &pid)
            if pid == getpid() { continue }

            var bundle: Unmanaged<CFString>? = nil
            var bsize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var baddr = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID,
                                                   mScope: kAudioObjectPropertyScopeGlobal,
                                                   mElement: kAudioObjectPropertyElementMain)
            _ = AudioObjectGetPropertyData(obj, &baddr, 0, nil, &bsize, &bundle)
            let name = bundle.map { $0.takeRetainedValue() as String } ?? "pid \(pid)"
            users.append(name.isEmpty ? "pid \(pid)" : name)
        }
        return users
    }

    /// Fallback for older systems: any input device running anywhere.
    private static func micInUseAnyDevice() -> Bool {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return false }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &devices) == noErr else { return false }
        for dev in devices {
            var saddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                   mScope: kAudioObjectPropertyScopeInput,
                                                   mElement: kAudioObjectPropertyElementMain)
            var ssize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(dev, &saddr, 0, nil, &ssize) == noErr, ssize > 0 else { continue }
            var running: UInt32 = 0
            var rsize = UInt32(MemoryLayout<UInt32>.size)
            var raddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                                   mScope: kAudioObjectPropertyScopeGlobal,
                                                   mElement: kAudioObjectPropertyElementMain)
            if AudioObjectGetPropertyData(dev, &raddr, 0, nil, &rsize, &running) == noErr, running != 0 { return true }
        }
        return false
    }

    // MARK: Camera

    private static func cameraInUse() -> Bool {
        var addr = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                             mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                             mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return false }
        var devices = [CMIODeviceID](repeating: 0, count: Int(size) / MemoryLayout<CMIODeviceID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &addr, 0, nil, size, &used, &devices) == noErr else { return false }
        for dev in devices {
            var raddr = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                                                  mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                                  mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
            var running: UInt32 = 0
            var rsize = UInt32(MemoryLayout<UInt32>.size)
            if CMIOObjectGetPropertyData(dev, &raddr, 0, nil, rsize, &rsize, &running) == noErr, running != 0 { return true }
        }
        return false
    }
}
