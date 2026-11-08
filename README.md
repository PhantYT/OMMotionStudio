# OM Motion Studio — DJI Osmo Mobile 7P

Native SwiftUI + CoreBluetooth iPhone application. The BLE protocol implementation is based on [shaun-xenon/osmo-remote](https://github.com/shaun-xenon/osmo-remote), whose README reports working pan/tilt control on a physical DJI Osmo Mobile 7P.

## Included

- BLE scan and connection.
- OM BLE service and characteristics: FFF0 / FFF4 / FFF5.
- DUML frame encoder/parser with CRC-8 and CRC-16.
- SPEED, PWM-center stop, absolute recenter and lock/follow/FPV packets.
- 25 Hz joystick packet scheduling and BLE write-without-response chunking.
- Incoming notification parsing and diagnostic log.
- Motion timeline/keyframes and iPhone camera recording.
- GitHub Actions workflow that creates an unsigned IPA artifact.

## Build

GitHub Actions builds the iOS app on a macOS runner. Open **Actions**, run or wait for **Build OM Motion Studio iOS**, then download the `OM-Motion-Studio-unsigned-IPA` artifact.

The IPA is unsigned. It cannot be installed directly by iOS; it must be signed with an Apple Developer certificate or a compatible personal sideloading method.

## Use with OM 7P

1. Close DJI Mimo and disconnect the gimbal from any other BLE central.
2. Turn on the OM 7P.
3. In OM Motion Studio open Bluetooth, scan and connect to the OM 7P.
4. Wait for FFF4 notifications and protocol initialization. The control screen shows the connection/protocol status.
5. Use the joystick. Release returns a neutral SPEED/PWM command.

This is unofficial reverse-engineered interoperability code. The source protocol is reported as working on OM7P, but this Swift port has not been validated on the user's physical unit from this environment. Use low speed first and keep the gimbal clear of obstructions.
