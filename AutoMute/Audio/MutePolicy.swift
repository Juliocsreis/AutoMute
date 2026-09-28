import Foundation

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

/// Pure state machine for mute/unmute decisions. Free of Core Audio for unit testing.
struct MutePolicy: Equatable {
    private(set) var state: MutePolicyState = .idle
    private(set) var mutedDeviceIDs: Set<UInt32> = []
    var isEnabled: Bool = true

    mutating func bluetoothBecameDefault(nonBluetoothDeviceIDs: [UInt32]) -> MutePolicyAction {
        guard isEnabled else { return MutePolicyAction() }

        var action = MutePolicyAction()
        if state == .mutedAfterLeave {
            action.unmuteDeviceIDs = takeMutedDeviceIDs()
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

    mutating func defaultLeftBluetooth(newDeviceID: UInt32) -> MutePolicyAction {
        guard isEnabled, state == .bluetoothActive else { return MutePolicyAction() }

        var action = MutePolicyAction(shouldNotify: true)
        if !mutedDeviceIDs.contains(newDeviceID) {
            action.muteDeviceIDs = [newDeviceID]
            mutedDeviceIDs.insert(newDeviceID)
        }
        state = .mutedAfterLeave
        return action
    }

    mutating func userUnmuted() -> MutePolicyAction {
        clearMutedReturningToIdle()
    }

    mutating func setEnabled(_ enabled: Bool) -> MutePolicyAction {
        isEnabled = enabled
        guard !enabled else { return MutePolicyAction() }
        return clearMutedReturningToIdle()
    }

    // MARK: - Private

    private mutating func takeMutedDeviceIDs() -> [UInt32] {
        let ids = Array(mutedDeviceIDs)
        mutedDeviceIDs.removeAll()
        return ids
    }

    private mutating func clearMutedReturningToIdle() -> MutePolicyAction {
        var action = MutePolicyAction()
        action.unmuteDeviceIDs = takeMutedDeviceIDs()
        state = .idle
        return action
    }
}
