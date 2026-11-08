# OM Motion Studio — Prototype 0.1

Native SwiftUI + CoreBluetooth diagnostic shell for researching DJI Osmo Mobile BLE connectivity.

## Current scope

- Scan nearby Bluetooth Low Energy devices.
- List discovered peripherals and signal strength.
- Connect to a selected peripheral.
- Enumerate GATT services and characteristics.
- Log characteristic properties.

**Safety:** this prototype does not write to any BLE characteristic and does not send movement commands. OM7P compatibility and its command protocol must be verified before enabling motion control.

## Build without owning a Mac

1. Create a GitHub repository and upload these files.
2. Ensure the default branch is named `main`.
3. Open **Actions** and run **Build iOS app** (or push a commit).
4. Download the `OMMotionStudio-unsigned-IPA` artifact from the completed workflow.
5. Sign/install it using a trusted sideloading method from a Windows PC. An unsigned IPA cannot be installed directly by iOS.

The GitHub runner provides macOS/Xcode for the build. Device installation still requires signing with an Apple ID and a compatible installation workflow.

## First hardware test

1. Install the prototype on the iPhone.
2. Close DJI Mimo and disconnect the gimbal from other devices.
3. Power on the OM7P.
4. Tap Scan and inspect the discovered BLE devices.
5. Connect to the likely OM7P entry and send the service/characteristic UUID list back for analysis.

Do not assume a device is the OM7P from its advertised name alone. Compare its advertised name, signal behaviour, services and characteristics. Do not send undocumented writes.
