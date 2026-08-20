import CoreAudio
import Foundation

struct SystemMicrophoneOperation: Sendable {
    let succeeded: Bool
    let state: SystemMicrophoneState
    let message: String
}

@MainActor
final class SystemMicrophoneController {
    private struct VolumeValue {
        let element: AudioObjectPropertyElement
        let original: Float32
        var lastKnownUnmuted: Float32?
        var zeroAppliedByController: Bool
    }

    private enum Route {
        case mute(original: UInt32)
        case volume([VolumeValue])
    }

    private enum RestoreOutcome {
        case restored
        case unavailable
        case failed
    }

    private enum DeviceReachability {
        case reachable
        case unavailable
        case indeterminate
    }

    private struct PreparedDevice {
        let id: AudioObjectID
        let shouldApplyDesiredState: Bool
    }

    private var routes: [AudioObjectID: Route] = [:]
    private var activeDevice: AudioObjectID?
    private var desiredMuted: Bool?
    private(set) var isSessionActive = false

    func beginSession() -> SystemMicrophoneState {
        if !isSessionActive {
            isSessionActive = true
            activeDevice = nil
            desiredMuted = nil
        }
        guard let prepared = prepareDefaultDevice() else {
            return prepareFailureState()
        }
        return readState(for: prepared.id)
    }

    func currentState() -> SystemMicrophoneState {
        guard isSessionActive else {
            return readCurrentStateWithoutCapturing()
        }
        guard let prepared = prepareDefaultDevice() else {
            return prepareFailureState()
        }
        if prepared.shouldApplyDesiredState, desiredMuted != nil {
            // A new default input device has not passed the current Facing
            // delay. Keep it muted until the user produces a new visual
            // transition instead of inheriting an earlier unmuted state.
            desiredMuted = true
            return applyMuted(true, to: prepared.id).state
        }
        return readState(for: prepared.id)
    }

    func setMuted(_ muted: Bool) -> SystemMicrophoneOperation {
        if !isSessionActive {
            _ = beginSession()
        }
        guard let prepared = prepareDefaultDevice() else {
            let state = prepareFailureState()
            return SystemMicrophoneOperation(succeeded: false, state: state, message: state.explanation)
        }
        desiredMuted = muted
        return applyMuted(muted, to: prepared.id)
    }

    @discardableResult
    func restoreOriginalState() -> SystemMicrophoneOperation {
        guard !routes.isEmpty else {
            isSessionActive = false
            activeDevice = nil
            desiredMuted = nil
            let state = readCurrentStateWithoutCapturing()
            return SystemMicrophoneOperation(succeeded: true, state: state, message: "无需恢复系统麦克风")
        }

        desiredMuted = nil
        activeDevice = nil
        var discardedUnavailableRoute = false
        for device in Array(routes.keys) {
            guard let route = routes[device] else { continue }
            switch restore(route, to: device) {
            case .restored:
                routes.removeValue(forKey: device)
            case .unavailable:
                routes.removeValue(forKey: device)
                discardedUnavailableRoute = true
            case .failed:
                break
            }
        }

        let succeeded = routes.isEmpty
        if succeeded {
            isSessionActive = false
        }
        let state = readCurrentStateWithoutCapturing()
        let successMessage = discardedUnavailableRoute
            ? "已恢复可用设备；已忽略断开的输入设备"
            : "已恢复原来的系统麦克风状态"
        return SystemMicrophoneOperation(
            succeeded: succeeded,
            state: state,
            message: succeeded ? successMessage : "系统麦克风原状态未能完全恢复"
        )
    }

    private func prepareDefaultDevice() -> PreparedDevice? {
        guard let device = defaultInputDevice() else { return nil }

        let deviceChanged = activeDevice != device
        if deviceChanged, let previous = activeDevice, let route = routes[previous] {
            switch restore(route, to: previous) {
            case .restored, .unavailable:
                routes.removeValue(forKey: previous)
            case .failed:
                break
            }
        }

        let routeWasMissing = routes[device] == nil
        activeDevice = device
        guard captureRouteIfNeeded(for: device) else { return nil }
        return PreparedDevice(
            id: device,
            shouldApplyDesiredState: deviceChanged || routeWasMissing
        )
    }

    private func applyMuted(_ muted: Bool, to device: AudioObjectID) -> SystemMicrophoneOperation {
        guard let route = routes[device] else {
            let state = SystemMicrophoneState.unavailable("当前输入设备不支持软件静音或输入音量控制")
            return SystemMicrophoneOperation(succeeded: false, state: state, message: state.explanation)
        }

        var writeSucceeded = false
        var failureMessage: String?
        switch route {
        case .mute:
            let current = readMute(device: device)
            writeSucceeded = current == (muted ? 1 : 0) || writeMute(muted, device: device)
        case .volume(let capturedValues):
            var values = capturedValues
            let result = applyVolumeMuted(muted, values: &values, device: device)
            writeSucceeded = result.succeeded
            failureMessage = result.message
            routes[device] = .volume(values)
        }

        let state = readState(for: device)
        let reachedTarget = (muted && state == .muted) || (!muted && state == .unmuted)
        let succeeded = writeSucceeded && reachedTarget
        let message: String
        if succeeded {
            message = muted ? "系统麦克风已禁用（静音）" : "系统麦克风已启用"
        } else if let failureMessage {
            message = failureMessage
        } else {
            message = "系统未确认麦克风状态已改变"
        }
        return SystemMicrophoneOperation(succeeded: succeeded, state: state, message: message)
    }

    private func applyVolumeMuted(
        _ muted: Bool,
        values: inout [VolumeValue],
        device: AudioObjectID
    ) -> (succeeded: Bool, message: String?) {
        var currentValues: [Float32] = []
        for value in values {
            guard let current = readVolume(device: device, element: value.element) else {
                return (false, "无法读取系统麦克风输入音量")
            }
            currentValues.append(current)
        }

        if !muted {
            let canReachNonzero = values.indices.contains { index in
                currentValues[index] > 0.001
                    || (values[index].zeroAppliedByController && values[index].lastKnownUnmuted != nil)
            }
            guard canReachNonzero else {
                return (false, "当前输入音量原本为 0；为避免擅自放大音量，请先手动设置输入音量")
            }
        }

        var allSucceeded = true
        for index in values.indices {
            let current = currentValues[index]
            if muted {
                if current > 0.001 {
                    values[index].lastKnownUnmuted = current
                    let wrote = writeVolume(0, device: device, element: values[index].element)
                    values[index].zeroAppliedByController = wrote
                    allSucceeded = wrote && allSucceeded
                }
            } else if current > 0.001 {
                values[index].lastKnownUnmuted = current
                values[index].zeroAppliedByController = false
            } else if values[index].zeroAppliedByController,
                      let target = values[index].lastKnownUnmuted {
                let wrote = writeVolume(target, device: device, element: values[index].element)
                if wrote {
                    values[index].zeroAppliedByController = false
                }
                allSucceeded = wrote && allSucceeded
            }
        }
        return (allSucceeded, allSucceeded ? nil : "无法修改系统麦克风输入音量")
    }

    private func restore(_ route: Route, to device: AudioObjectID) -> RestoreOutcome {
        switch routeReachability(route, on: device) {
        case .reachable:
            break
        case .unavailable:
            return .unavailable
        case .indeterminate:
            return .failed
        }

        var succeeded = true
        switch route {
        case .mute(let original):
            succeeded = writeMute(original != 0, device: device)
        case .volume(let values):
            for value in values {
                succeeded = writeVolume(value.original, device: device, element: value.element) && succeeded
            }
        }
        return succeeded ? .restored : .failed
    }

    private func routeReachability(_ route: Route, on device: AudioObjectID) -> DeviceReachability {
        var aliveAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(device, &aliveAddress) {
            var alive: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            let status = AudioObjectGetPropertyData(device, &aliveAddress, 0, nil, &size, &alive)
            if status == kAudioHardwareBadObjectError { return .unavailable }
            guard status == noErr else { return .indeterminate }
            guard alive != 0 else { return .unavailable }
        } else {
            var classAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyClass,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var objectClass: AudioClassID = 0
            var size = UInt32(MemoryLayout<AudioClassID>.size)
            let status = AudioObjectGetPropertyData(device, &classAddress, 0, nil, &size, &objectClass)
            if status == kAudioHardwareBadObjectError { return .unavailable }
            guard status == noErr else { return .indeterminate }
        }

        switch route {
        case .mute:
            var address = inputAddress(
                selector: kAudioDevicePropertyMute,
                element: kAudioObjectPropertyElementMain
            )
            return AudioObjectHasProperty(device, &address) ? .reachable : .indeterminate
        case .volume(let values):
            let allPropertiesRemain = values.allSatisfy { value in
                var address = inputAddress(
                    selector: kAudioDevicePropertyVolumeScalar,
                    element: value.element
                )
                return AudioObjectHasProperty(device, &address)
            }
            return allPropertiesRemain ? .reachable : .indeterminate
        }
    }

    private func prepareFailureState() -> SystemMicrophoneState {
        defaultInputDevice() == nil
            ? .unavailable("未找到系统默认输入设备")
            : .unavailable("当前输入设备不支持软件静音或输入音量控制")
    }

    private func captureRouteIfNeeded(for device: AudioObjectID) -> Bool {
        if routes[device] != nil { return true }

        if isSettable(selector: kAudioDevicePropertyMute, device: device, element: kAudioObjectPropertyElementMain),
           let original = readMute(device: device) {
            routes[device] = .mute(original: original)
            return true
        }

        let main = kAudioObjectPropertyElementMain
        if isSettable(selector: kAudioDevicePropertyVolumeScalar, device: device, element: main),
           let original = readVolume(device: device, element: main) {
            routes[device] = .volume([
                VolumeValue(
                    element: main,
                    original: original,
                    lastKnownUnmuted: original > 0.001 ? original : nil,
                    zeroAppliedByController: false
                )
            ])
            return true
        }

        var values: [VolumeValue] = []
        for element in AudioObjectPropertyElement(1)...AudioObjectPropertyElement(32) {
            guard isSettable(selector: kAudioDevicePropertyVolumeScalar, device: device, element: element),
                  let original = readVolume(device: device, element: element) else { continue }
            values.append(VolumeValue(
                element: element,
                original: original,
                lastKnownUnmuted: original > 0.001 ? original : nil,
                zeroAppliedByController: false
            ))
        }
        guard !values.isEmpty else { return false }
        routes[device] = .volume(values)
        return true
    }

    private func readState(for device: AudioObjectID) -> SystemMicrophoneState {
        guard let route = routes[device] else {
            return .unavailable("当前输入设备没有可用的静音控制")
        }
        switch route {
        case .mute:
            guard let value = readMute(device: device) else {
                return .unavailable("无法读取系统麦克风静音状态")
            }
            return value == 0 ? .unmuted : .muted
        case .volume(let values):
            let current = values.compactMap { readVolume(device: device, element: $0.element) }
            guard current.count == values.count else {
                return .unavailable("无法读取系统麦克风输入音量")
            }
            return current.allSatisfy { $0 <= 0.001 } ? .muted : .unmuted
        }
    }

    private func readCurrentStateWithoutCapturing() -> SystemMicrophoneState {
        guard let device = defaultInputDevice() else {
            return .unavailable("未找到系统默认输入设备")
        }
        if let value = readMute(device: device) {
            return value == 0 ? .unmuted : .muted
        }
        if let value = readVolume(device: device, element: kAudioObjectPropertyElementMain) {
            return value <= 0.001 ? .muted : .unmuted
        }
        return .unknown
    }

    private func defaultInputDevice() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &device
        )
        guard status == noErr, device != kAudioObjectUnknown else { return nil }
        return device
    }

    private func isSettable(
        selector: AudioObjectPropertySelector,
        device: AudioObjectID,
        element: AudioObjectPropertyElement
    ) -> Bool {
        var address = inputAddress(selector: selector, element: element)
        guard AudioObjectHasProperty(device, &address) else { return false }
        var settable = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    private func readMute(device: AudioObjectID) -> UInt32? {
        var address = inputAddress(selector: kAudioDevicePropertyMute, element: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private func writeMute(_ muted: Bool, device: AudioObjectID) -> Bool {
        var address = inputAddress(selector: kAudioDevicePropertyMute, element: kAudioObjectPropertyElementMain)
        var value: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectSetPropertyData(device, &address, 0, nil, size, &value) == noErr
    }

    private func readVolume(device: AudioObjectID, element: AudioObjectPropertyElement) -> Float32? {
        var address = inputAddress(selector: kAudioDevicePropertyVolumeScalar, element: element)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private func writeVolume(
        _ value: Float32,
        device: AudioObjectID,
        element: AudioObjectPropertyElement
    ) -> Bool {
        var address = inputAddress(selector: kAudioDevicePropertyVolumeScalar, element: element)
        var clamped = min(max(value, 0), 1)
        let size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectSetPropertyData(device, &address, 0, nil, size, &clamped) == noErr
    }

    private func inputAddress(
        selector: AudioObjectPropertySelector,
        element: AudioObjectPropertyElement
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: element
        )
    }
}
