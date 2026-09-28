import Foundation

/// Pure state machine for when AutoMute should mute or unmute.
/// Free of Core Audio so unit tests can drive transitions without hardware.
enum MutePolicyState: Equatable {
    case idle
    case bluetoothActive
    case mutedAfterLeave
}

struct MutePolicyAction: Equatable {
    var muteDeviceIDs: [UInt32] = []
    var unmuteDeviceIDs: [UInt32] = []
    var shouldNotify: Bool = false
}

struct MutePolicy: Equatable {
    private(set) var state: MutePolicyState = .idle
    private(set) var mutedDeviceIDs: Set<UInt32> = []
    var isEnabled: Bool = true

    /// Called when the default output becomes a Bluetooth device.
    mutating func bluetoothBecameDefault(nonBluetoothDeviceIDs: [UInt32]) -> MutePolicyAction {
        guard isEnabled else {
            return MutePolicyAction()
        }

        var action = MutePolicyAction()

        if state == .mutedAfterLeave, !mutedDeviceIDs.isEmpty {
            action.unmuteDeviceIDs = Array(mutedDeviceIDs)
            mutedDeviceIDs.removeAll()
        }

        // Pre-arm non-Bluetooth outputs so a later handoff is already silent.
        let toMute = nonBluetoothDeviceIDs.filter { !mutedDeviceIDs.contains($0) }
        if !toMute.isEmpty {
            action.muteDeviceIDs = toMute
            mutedDeviceIDs.formUnion(toMute)
        }

        state = .bluetoothActive
        return action
    }

    /// Called when the default output leaves Bluetooth for `newDeviceID`.
    mutating func defaultLeftBluetooth(newDeviceID: UInt32) -> MutePolicyAction {
        guard isEnabled else {
            return MutePolicyAction()
        }
        guard state == .bluetoothActive else {
            return MutePolicyAction()
        }

        var action = MutePolicyAction()
        if !mutedDeviceIDs.contains(newDeviceID) {
            action.muteDeviceIDs = [newDeviceID]
            mutedDeviceIDs.insert(newDeviceID)
        }
        action.shouldNotify = true
        state = .mutedAfterLeave
        return action
    }

    /// Manual unmute from the menu bar.
    mutating func userUnmuted() -> MutePolicyAction {
        var action = MutePolicyAction()
        if !mutedDeviceIDs.isEmpty {
            action.unmuteDeviceIDs = Array(mutedDeviceIDs)
            mutedDeviceIDs.removeAll()
        }
        state = .idle
        return action
    }

    /// Enable or disable monitoring. Disabling unmutes anything we muted.
    mutating func setEnabled(_ enabled: Bool) -> MutePolicyAction {
        isEnabled = enabled
        guard !enabled else {
            return MutePolicyAction()
        }

        var action = MutePolicyAction()
        if !mutedDeviceIDs.isEmpty {
            action.unmuteDeviceIDs = Array(mutedDeviceIDs)
            mutedDeviceIDs.removeAll()
        }
        state = .idle
        return action
    }

    /// Tear down on quit: unmute devices we still own.
    mutating func prepareForQuit() -> MutePolicyAction {
        setEnabled(false)
    }
}
