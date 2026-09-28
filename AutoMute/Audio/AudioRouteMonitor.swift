import AppKit
import CoreAudio
import Foundation

/// Watches Core Audio default-output and device-list changes, then applies `MutePolicy`.
@MainActor
final class AudioRouteMonitor: ObservableObject {
    @Published private(set) var statusText: String = "Idle"
    @Published private(set) var defaultDeviceName: String = "—"
    @Published var isEnabled: Bool = true {
        didSet {
            apply(policy.setEnabled(isEnabled))
            if isEnabled {
                evaluateCurrentRoute(notifyOnMute: false)
            }
            refreshStatus()
        }
    }

    private var policy = MutePolicy()
    private var isListening = false
    private var lastDefaultDeviceID: AudioDeviceID?
    private var lastWasBluetooth = false

    private let defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private let devicesAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    func start() {
        guard !isListening else { return }
        isListening = true

        addListener(defaultOutputAddress, context: self) { monitor in
            monitor.handleRouteChange()
        }
        addListener(devicesAddress, context: self) { monitor in
            monitor.handleRouteChange()
        }

        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleRouteChange()
            }
        }

        evaluateCurrentRoute(notifyOnMute: false)
        refreshStatus()
    }

    func stop() {
        guard isListening else { return }
        isListening = false
        removeListener(defaultOutputAddress)
        removeListener(devicesAddress)
        apply(policy.prepareForQuit())
        refreshStatus()
    }

    func unmuteNow() {
        apply(policy.userUnmuted())
        refreshStatus()
    }

    // MARK: - Route evaluation

    private func handleRouteChange() {
        evaluateCurrentRoute(notifyOnMute: true)
        refreshStatus()
    }

    private func evaluateCurrentRoute(notifyOnMute: Bool) {
        guard let deviceID = CoreAudioDevice.defaultOutputDeviceID() else {
            defaultDeviceName = "—"
            return
        }

        defaultDeviceName = CoreAudioDevice.name(of: deviceID)
        let isBluetooth = CoreAudioDevice.isBluetooth(deviceID)
        let nonBluetooth = CoreAudioDevice.nonBluetoothOutputDeviceIDs()

        defer {
            lastDefaultDeviceID = deviceID
            lastWasBluetooth = isBluetooth
        }

        if isBluetooth {
            let action = policy.bluetoothBecameDefault(nonBluetoothDeviceIDs: nonBluetooth)
            apply(action, allowNotify: false)
            return
        }

        // Left Bluetooth for a non-Bluetooth default.
        if lastWasBluetooth || policy.state == .bluetoothActive {
            var action = policy.defaultLeftBluetooth(newDeviceID: deviceID)
            if !notifyOnMute {
                action.shouldNotify = false
            }
            apply(action, allowNotify: notifyOnMute)
        }
    }

    private func apply(_ action: MutePolicyAction, allowNotify: Bool = true) {
        // Unmute first so a reconnect's re-pre-arm can mute again afterward.
        for id in action.unmuteDeviceIDs {
            CoreAudioDevice.setMuted(false, deviceID: id)
        }
        for id in action.muteDeviceIDs {
            CoreAudioDevice.setMuted(true, deviceID: id)
        }
        if allowNotify, action.shouldNotify {
            MuteNotifier.notifyMuted()
        }
    }

    private func refreshStatus() {
        guard isEnabled else {
            statusText = "Disabled"
            return
        }
        switch policy.state {
        case .idle:
            statusText = "Watching"
        case .bluetoothActive:
            statusText = "Bluetooth"
        case .mutedAfterLeave:
            statusText = "Muted"
        }
    }

    // MARK: - Core Audio listeners

    private func addListener(
        _ address: AudioObjectPropertyAddress,
        context: AudioRouteMonitor,
        handler: @escaping (AudioRouteMonitor) -> Void
    ) {
        var address = address
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            Task { @MainActor in
                handler(context)
            }
        }
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
        // Retain blocks via associated storage keyed by selector.
        listenerBlocks[address.mSelector] = block
    }

    private func removeListener(_ address: AudioObjectPropertyAddress) {
        var address = address
        if let block = listenerBlocks.removeValue(forKey: address.mSelector) {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                DispatchQueue.main,
                block
            )
        }
    }

    private var listenerBlocks: [AudioObjectPropertySelector: AudioObjectPropertyListenerBlock] = [:]
}
