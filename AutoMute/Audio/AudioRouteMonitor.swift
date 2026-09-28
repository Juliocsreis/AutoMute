import AppKit
import CoreAudio
import Foundation

enum MonitorStatus: Equatable {
    case watching
    case bluetooth
    case muted
    case disabled

    var title: String {
        switch self {
        case .watching: return "Watching"
        case .bluetooth: return "Bluetooth"
        case .muted: return "Muted"
        case .disabled: return "Disabled"
        }
    }

    var symbolName: String {
        switch self {
        case .watching: return "ear"
        case .bluetooth: return "headphones"
        case .muted: return "speaker.slash.fill"
        case .disabled: return "speaker.slash"
        }
    }
}

/// Watches Core Audio default-output and device-list changes, then applies `MutePolicy`.
@MainActor
final class AudioRouteMonitor: ObservableObject {
    @Published private(set) var status: MonitorStatus = .watching
    @Published private(set) var defaultDeviceName: String = "—"
    @Published var isEnabled: Bool = true {
        didSet {
            applyAndRefresh(policy.setEnabled(isEnabled), allowNotify: false)
            if isEnabled {
                evaluateCurrentRoute(notifyOnMute: false)
            }
        }
    }

    private var policy = MutePolicy()
    private var isListening = false
    private var lastDefaultDeviceID: AudioDeviceID?
    private var lastWasBluetooth = false
    private var pendingEvaluation: DispatchWorkItem?
    private var wakeObserver: NSObjectProtocol?

    private var listenerBlocks: [AudioObjectPropertySelector: AudioObjectPropertyListenerBlock] = [:]

    func start() {
        guard !isListening else { return }
        isListening = true

        addListener(CoreAudioDevice.defaultOutputAddress)
        addListener(CoreAudioDevice.devicesAddress)

        wakeObserver = NotificationCenter.default.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleRouteEvaluation(notifyOnMute: true)
            }
        }

        evaluateCurrentRoute(notifyOnMute: false)
    }

    func stop() {
        guard isListening else { return }
        isListening = false
        pendingEvaluation?.cancel()
        pendingEvaluation = nil
        removeListener(CoreAudioDevice.defaultOutputAddress)
        removeListener(CoreAudioDevice.devicesAddress)
        if let wakeObserver {
            NotificationCenter.default.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        applyAndRefresh(policy.setEnabled(false), allowNotify: false)
    }

    func unmuteNow() {
        applyAndRefresh(policy.userUnmuted(), allowNotify: false)
    }

    // MARK: - Route evaluation

    private func scheduleRouteEvaluation(notifyOnMute: Bool) {
        pendingEvaluation?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.evaluateCurrentRoute(notifyOnMute: notifyOnMute)
        }
        pendingEvaluation = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: work)
    }

    private func evaluateCurrentRoute(notifyOnMute: Bool) {
        guard let deviceID = CoreAudioDevice.defaultOutputDeviceID() else {
            defaultDeviceName = "—"
            lastDefaultDeviceID = nil
            lastWasBluetooth = false
            refreshStatus()
            return
        }

        let isBluetooth = CoreAudioDevice.isBluetooth(deviceID)
        let routeUnchanged = lastDefaultDeviceID == deviceID && lastWasBluetooth == isBluetooth

        if !routeUnchanged {
            defaultDeviceName = CoreAudioDevice.name(of: deviceID)
        }

        defer {
            lastDefaultDeviceID = deviceID
            lastWasBluetooth = isBluetooth
        }

        if isBluetooth {
            // Only enumerate fallbacks when Bluetooth is (or becomes) active.
            let nonBluetooth = CoreAudioDevice.nonBluetoothOutputDeviceIDs()
            applyAndRefresh(
                policy.bluetoothBecameDefault(nonBluetoothDeviceIDs: nonBluetooth),
                allowNotify: false
            )
            return
        }

        if policy.state == .bluetoothActive {
            applyAndRefresh(
                policy.defaultLeftBluetooth(newDeviceID: deviceID),
                allowNotify: notifyOnMute
            )
            return
        }

        if !routeUnchanged {
            refreshStatus()
        }
    }

    private func applyAndRefresh(_ action: MutePolicyAction, allowNotify: Bool) {
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
        refreshStatus()
    }

    private func refreshStatus() {
        guard isEnabled else {
            status = .disabled
            return
        }
        switch policy.state {
        case .idle:
            status = .watching
        case .bluetoothActive:
            status = .bluetooth
        case .mutedAfterLeave:
            status = .muted
        }
    }

    // MARK: - Core Audio listeners

    private func addListener(_ address: AudioObjectPropertyAddress) {
        var address = address
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                self?.scheduleRouteEvaluation(notifyOnMute: true)
            }
        }
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
        listenerBlocks[address.mSelector] = block
    }

    private func removeListener(_ address: AudioObjectPropertyAddress) {
        var address = address
        guard let block = listenerBlocks.removeValue(forKey: address.mSelector) else { return }
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
    }
}
