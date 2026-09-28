# AutoMute

Menu-bar macOS app that mutes your Mac’s speakers when Bluetooth headphones (AirPods, Beats, or any BT headset) leave this Mac — for example when they connect to an iPhone.

## Requirements

- macOS 14 or later
- Xcode 15+ (Swift 5.9+)

## Build & run

1. Open `AutoMute.xcodeproj` in Xcode.
2. Select the **AutoMute** scheme.
3. Set your signing team under **Signing & Capabilities** (Personal Team is fine for local use).
4. Press **⌘R**.

The app appears only in the menu bar (no Dock icon). Allow notifications when prompted so you get a mute alert.

## How it works

1. Watches the system default audio output via Core Audio.
2. When the default device is Bluetooth, it **pre-mutes** non-Bluetooth outputs (speakers) so a later handoff stays silent.
3. When the default leaves Bluetooth (iPhone handoff, out of range, or manual switch to Speakers), it mutes the new output and shows a notification.
4. When Bluetooth headphones become the default again, it **unmutes** automatically.

## Menu

| Item | Action |
| --- | --- |
| Enabled | Turn monitoring on/off |
| Unmute Now | Clear mute without waiting for headphones |
| Launch at Login | Register with `SMAppService` |
| Quit AutoMute | Unmute owned devices and exit |

## Manual verification

1. Connect AirPods (or any Bluetooth headphones) to the Mac and play audio.
2. On your iPhone, connect to the same headphones (or switch output to Speakers in Control Center).
3. Confirm the Mac’s speakers stay silent and a notification appears: *“Headphones left this Mac. Output muted.”*
4. Switch the headphones back to the Mac — audio should return (AutoMute unmutes).
5. Quit AutoMute and repeat a handoff — the Mac should behave normally again.

## Tests

```bash
xcodebuild test -scheme AutoMute -destination 'platform=macOS'
```

`MutePolicy` unit tests cover idle / Bluetooth / muted transitions without hardware.

## Notes

- The app is **not sandboxed** so Core Audio mute works reliably.
- Signing with your Apple ID is enough for local use. Use Developer ID + notarization only if you distribute outside your Mac.
- Taking an earbud out of your ear does not change the default device, so it does not mute — by design.
