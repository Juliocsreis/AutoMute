import XCTest
@testable import AutoMute

final class MutePolicyTests: XCTestCase {
    func testLaunchWithSpeakersStaysIdle() {
        var policy = MutePolicy()
        // No bluetoothBecameDefault / defaultLeftBluetooth called.
        XCTAssertEqual(policy.state, .idle)
        XCTAssertTrue(policy.mutedDeviceIDs.isEmpty)
    }

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
        var policy = MutePolicy()
        _ = policy.bluetoothBecameDefault(nonBluetoothDeviceIDs: [10])
        let action = policy.defaultLeftBluetooth(newDeviceID: 10)

        XCTAssertEqual(policy.state, .mutedAfterLeave)
        XCTAssertTrue(action.muteDeviceIDs.isEmpty) // already pre-armed
        XCTAssertTrue(action.shouldNotify)
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
        var policy = MutePolicy()
        _ = policy.bluetoothBecameDefault(nonBluetoothDeviceIDs: [10])
        _ = policy.defaultLeftBluetooth(newDeviceID: 10)

        let action = policy.bluetoothBecameDefault(nonBluetoothDeviceIDs: [10, 20])

        XCTAssertEqual(policy.state, .bluetoothActive)
        XCTAssertEqual(Set(action.unmuteDeviceIDs), Set([10]))
        XCTAssertEqual(Set(action.muteDeviceIDs), Set([10, 20]))
        XCTAssertFalse(action.shouldNotify)
        XCTAssertEqual(policy.mutedDeviceIDs, Set([10, 20]))
    }

    func testUserUnmuteClearsMutedState() {
        var policy = MutePolicy()
        _ = policy.bluetoothBecameDefault(nonBluetoothDeviceIDs: [10])
        _ = policy.defaultLeftBluetooth(newDeviceID: 10)

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

    func testPrepareForQuitUnmutes() {
        var policy = MutePolicy()
        _ = policy.bluetoothBecameDefault(nonBluetoothDeviceIDs: [7])
        let action = policy.prepareForQuit()

        XCTAssertEqual(action.unmuteDeviceIDs, [7])
        XCTAssertEqual(policy.state, .idle)
        XCTAssertFalse(policy.isEnabled)
    }
}
