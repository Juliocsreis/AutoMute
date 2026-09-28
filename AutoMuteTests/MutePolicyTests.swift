import XCTest
@testable import AutoMute

final class MutePolicyTests: XCTestCase {
    func testBluetoothBecameDefaultPreArmsSpeakers() {
        var policy = MutePolicy()
        let action = policy.bluetoothBecameDefault(nonBluetoothDeviceIDs: [10, 20])

        XCTAssertEqual(policy.state, .bluetoothActive)
        XCTAssertEqual(Set(action.muteDeviceIDs), Set([10, 20]))
        XCTAssertTrue(action.unmuteDeviceIDs.isEmpty)
        XCTAssertFalse(action.shouldNotify)
        XCTAssertEqual(policy.mutedDeviceIDs, Set([10, 20]))
    }

    func testLeavingBluetoothMutesAndNotifies() {
        let policy = policyAfterLeavingBluetooth(preArmed: [10], newDeviceID: 10)

        XCTAssertEqual(policy.state, .mutedAfterLeave)
        XCTAssertEqual(policy.mutedDeviceIDs, Set([10]))
    }

    func testLeavingBluetoothMutesNewDeviceIfNotPreArmed() {
        var policy = MutePolicy()
        _ = policy.bluetoothBecameDefault(nonBluetoothDeviceIDs: [10])
        let action = policy.defaultLeftBluetooth(newDeviceID: 99)

        XCTAssertEqual(action.muteDeviceIDs, [99])
        XCTAssertTrue(action.shouldNotify)
        XCTAssertEqual(policy.mutedDeviceIDs, Set([10, 99]))
    }

    func testBluetoothReturnUnmutesThenPreArms() {
        var policy = policyAfterLeavingBluetooth(preArmed: [10], newDeviceID: 10)
        let action = policy.bluetoothBecameDefault(nonBluetoothDeviceIDs: [10, 20])

        XCTAssertEqual(policy.state, .bluetoothActive)
        XCTAssertEqual(Set(action.unmuteDeviceIDs), Set([10]))
        XCTAssertEqual(Set(action.muteDeviceIDs), Set([10, 20]))
        XCTAssertFalse(action.shouldNotify)
        XCTAssertEqual(policy.mutedDeviceIDs, Set([10, 20]))
    }

    func testUserUnmuteClearsMutedState() {
        var policy = policyAfterLeavingBluetooth(preArmed: [10], newDeviceID: 10)
        let action = policy.userUnmuted()

        XCTAssertEqual(policy.state, .idle)
        XCTAssertEqual(action.unmuteDeviceIDs, [10])
        XCTAssertTrue(policy.mutedDeviceIDs.isEmpty)
    }

    func testDisableUnmutesAndReturnsToIdle() {
        var policy = MutePolicy()
        _ = policy.bluetoothBecameDefault(nonBluetoothDeviceIDs: [5])
        let action = policy.setEnabled(false)

        XCTAssertFalse(policy.isEnabled)
        XCTAssertEqual(policy.state, .idle)
        XCTAssertEqual(action.unmuteDeviceIDs, [5])
        XCTAssertTrue(policy.mutedDeviceIDs.isEmpty)
    }

    func testDefaultLeftBluetoothIgnoredWhenIdle() {
        var policy = MutePolicy()
        let action = policy.defaultLeftBluetooth(newDeviceID: 10)

        XCTAssertEqual(policy.state, .idle)
        XCTAssertTrue(action.muteDeviceIDs.isEmpty)
        XCTAssertFalse(action.shouldNotify)
    }

    func testDisabledIgnoresBluetoothEvents() {
        var policy = MutePolicy()
        _ = policy.setEnabled(false)
        let action = policy.bluetoothBecameDefault(nonBluetoothDeviceIDs: [1])

        XCTAssertEqual(policy.state, .idle)
        XCTAssertTrue(action.muteDeviceIDs.isEmpty)
    }

    // MARK: - Helpers

    private func policyAfterLeavingBluetooth(
        preArmed: [UInt32],
        newDeviceID: UInt32
    ) -> MutePolicy {
        var policy = MutePolicy()
        _ = policy.bluetoothBecameDefault(nonBluetoothDeviceIDs: preArmed)
        _ = policy.defaultLeftBluetooth(newDeviceID: newDeviceID)
        return policy
    }
}
