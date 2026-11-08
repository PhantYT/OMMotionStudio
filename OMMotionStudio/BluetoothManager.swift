
import Foundation
import CoreBluetooth

struct GimbalDevice: Identifiable {
    let id: UUID
    let name: String
    let rssi: Int
    let peripheral: CBPeripheral
}

struct GATTCharacteristicInfo: Identifiable {
    let id: String
    let properties: String
    let isNotifying: Bool
    let value: String
}

struct GATTServiceInfo: Identifiable {
    let id: String
    var characteristics: [GATTCharacteristicInfo]
}

@MainActor
final class BluetoothManager: NSObject, ObservableObject {

    @Published private(set) var stateText = "Проверяем Bluetooth..."
    @Published private(set) var devices: [GimbalDevice] = []
    @Published private(set) var connectedName: String?
    @Published private(set) var services: [GATTServiceInfo] = []
    @Published private(set) var log: [String] = []

    private var central: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func startScan() {
        guard central.state == .poweredOn else {
            appendLog("Bluetooth недоступен: \(stateText)")
            return
        }

        devices.removeAll()
        services.removeAll()

        appendLog("Начато BLE-сканирование")

        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    func stopScan() {
        central.stopScan()
        appendLog("Сканирование остановлено")
    }

    func connect(_ device: GimbalDevice) {
        stopScan()
        appendLog("Подключение к \(device.name)...")
        central.connect(device.peripheral, options: nil)
    }

    func disconnect() {
        guard let peripheral = connectedPeripheral else { return }
        central.cancelPeripheralConnection(peripheral)
    }

    func clearLog() {
        log.removeAll()
    }

    private func appendLog(_ message: String) {
        log.insert(
            "[\(Date().formatted(date: .omitted, time: .standard))] \(message)",
            at: 0
        )

        if log.count > 200 {
            log.removeLast(log.count - 200)
        }
    }

    private func propertiesText(_ properties: CBCharacteristicProperties) -> String {
        var result: [String] = []

        if properties.contains(.read) { result.append("READ") }
        if properties.contains(.write) { result.append("WRITE") }
        if properties.contains(.writeWithoutResponse) {
            result.append("WRITE WITHOUT RESPONSE")
        }
        if properties.contains(.notify) { result.append("NOTIFY") }
        if properties.contains(.indicate) { result.append("INDICATE") }

        return result.isEmpty ? "UNKNOWN" : result.joined(separator: ", ")
    }

    private func hex(_ data: Data?) -> String {
        guard let data, !data.isEmpty else { return "Нет данных" }

        return data.map {
            String(format: "%02X", $0)
        }.joined(separator: " ")
    }

    private func updateCharacteristic(_ characteristic: CBCharacteristic) {
        guard let serviceID = characteristic.service?.uuid.uuidString,
              let serviceIndex = services.firstIndex(where: { $0.id == serviceID })
        else { return }

        let info = GATTCharacteristicInfo(
            id: characteristic.uuid.uuidString,
            properties: propertiesText(characteristic.properties),
            isNotifying: characteristic.isNotifying,
            value: hex(characteristic.value)
        )

        if let index = services[serviceIndex].characteristics.firstIndex(
            where: { $0.id == info.id }
        ) {
            services[serviceIndex].characteristics[index] = info
        } else {
            services[serviceIndex].characteristics.append(info)
        }
    }
}

extension BluetoothManager: CBCentralManagerDelegate {

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state

        Task { @MainActor in
            switch state {
            case .poweredOn:
                self.stateText = "Bluetooth включён"
            case .poweredOff:
                self.stateText = "Bluetooth выключен"
            case .unauthorized:
                self.stateText = "Нет разрешения Bluetooth"
            case .unsupported:
                self.stateText = "Bluetooth не поддерживается"
            case .resetting:
                self.stateText = "Bluetooth перезапускается"
            case .unknown:
                self.stateText = "Состояние неизвестно"
            @unknown default:
                self.stateText = "Неизвестное состояние"
            }

            self.appendLog(self.stateText)
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? "Без имени"

        let id = peripheral.identifier
        let signal = RSSI.intValue

        Task { @MainActor in
            if let index = self.devices.firstIndex(where: { $0.id == id }) {
                let old = self.devices[index]

                self.devices[index] = GimbalDevice(
                    id: id,
                    name: old.name,
                    rssi: signal,
                    peripheral: old.peripheral
                )
            } else {
                self.devices.append(
                    GimbalDevice(
                        id: id,
                        name: name,
                        rssi: signal,
                        peripheral: peripheral
                    )
                )
            }

            self.devices.sort { $0.rssi > $1.rssi }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        peripheral.delegate = self
        peripheral.discoverServices(nil)

        Task { @MainActor in
            self.connectedPeripheral = peripheral
            self.connectedName = peripheral.name ?? "DJI OM"
            self.services.removeAll()
            self.appendLog("Подключено: \(self.connectedName ?? "DJI")")
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        let message = error?.localizedDescription ?? "Неизвестная ошибка"

        Task { @MainActor in
            self.appendLog("Ошибка подключения: \(message)")
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        let message = error?.localizedDescription

        Task { @MainActor in
            self.connectedPeripheral = nil
            self.connectedName = nil
            self.services.removeAll()

            self.appendLog(
                "Соединение разорвано\(message.map { ": \($0)" } ?? "")"
            )
        }
    }
}

extension BluetoothManager: CBPeripheralDelegate {

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        let found = peripheral.services ?? []

        Task { @MainActor in
            if let error {
                self.appendLog("Ошибка служб: \(error.localizedDescription)")
            }

            self.appendLog("Обнаружено служб: \(found.count)")

            self.services = found.map {
                GATTServiceInfo(
                    id: $0.uuid.uuidString,
                    characteristics: []
                )
            }
        }

        for service in found {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        let characteristics = service.characteristics ?? []
        let serviceID = service.uuid.uuidString

        Task { @MainActor in
            if let error {
                self.appendLog("Ошибка характеристик: \(error.localizedDescription)")
            }

            self.appendLog(
                "Служба \(serviceID): \(characteristics.count) характеристик"
            )
        }

        for characteristic in characteristics {
            if characteristic.properties.contains(.read) {
                peripheral.readValue(for: characteristic)
            }

            if characteristic.properties.contains(.notify)
                || characteristic.properties.contains(.indicate) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        let uuid = characteristic.uuid.uuidString
        let data = characteristic.value
        let bytes = data.map {
            $0.map { String(format: "%02X", $0) }.joined(separator: " ")
        } ?? "Нет данных"

        let message = error?.localizedDescription

        Task { @MainActor in
            if let message {
                self.appendLog("Ошибка чтения \(uuid): \(message)")
            } else {
                self.appendLog("Получены данные \(uuid): \(bytes)")
            }

            self.updateCharacteristic(characteristic)
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        let uuid = characteristic.uuid.uuidString
        let enabled = characteristic.isNotifying
        let message = error?.localizedDescription

        Task { @MainActor in
            if let message {
                self.appendLog("Ошибка Notify \(uuid): \(message)")
            } else {
                self.appendLog(
                    "Notify \(uuid): \(enabled ? "включён" : "выключен")"
                )
            }

            self.updateCharacteristic(characteristic)
        }
    }
}
