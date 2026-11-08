import Foundation
import CoreBluetooth

struct DiscoveredGimbal: Identifiable {
    let id: UUID
    let name: String
    let rssi: Int
    let peripheral: CBPeripheral
}

@MainActor
final class BluetoothManager: NSObject, ObservableObject {
    @Published private(set) var stateText = "Проверяем Bluetooth…"
    @Published private(set) var devices: [DiscoveredGimbal] = []
    @Published private(set) var connectedName: String?
    @Published private(set) var discoveredServices: [String] = []
    @Published private(set) var log: [String] = []

    private var central: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func startScan() {
        guard central.state == .poweredOn else {
            addLog("Bluetooth пока недоступен.")
            return
        }
        devices.removeAll()
        discoveredServices.removeAll()
        addLog("Начато BLE-сканирование.")
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScan() {
        central.stopScan()
        addLog("Сканирование остановлено.")
    }

    func connect(_ device: DiscoveredGimbal) {
        stopScan()
        addLog("Подключение к \(device.name)…")
        central.connect(device.peripheral, options: nil)
    }

    func disconnect() {
        guard let peripheral = connectedPeripheral else { return }
        central.cancelPeripheralConnection(peripheral)
    }

    private func addLog(_ message: String) {
        log.insert(message, at: 0)
        if log.count > 30 { log.removeLast() }
    }
}

extension BluetoothManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                self.stateText = "Bluetooth включён"
            case .poweredOff:
                self.stateText = "Bluetooth выключен"
            case .unauthorized:
                self.stateText = "Нет разрешения Bluetooth"
            case .unsupported:
                self.stateText = "Bluetooth LE не поддерживается"
            case .resetting:
                self.stateText = "Bluetooth перезапускается"
            case .unknown:
                self.stateText = "Состояние Bluetooth неизвестно"
            @unknown default:
                self.stateText = "Неизвестное состояние"
            }
            self.addLog(self.stateText)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any],
                                    rssi RSSI: NSNumber) {
        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? "Без имени"
        let id = peripheral.identifier
        let rssi = RSSI.intValue

        Task { @MainActor in
            guard !self.devices.contains(where: { $0.id == id }) else { return }
            self.devices.append(DiscoveredGimbal(id: id, name: name,
                                                 rssi: rssi, peripheral: peripheral))
            self.devices.sort { $0.rssi > $1.rssi }
            self.addLog("Найдено BLE-устройство: \(name), RSSI \(rssi)")
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        Task { @MainActor in
            self.connectedPeripheral = peripheral
            self.connectedName = peripheral.name ?? "DJI / неизвестное устройство"
            self.addLog("Подключено: \(self.connectedName ?? "устройство")")
        }
        peripheral.discoverServices(nil)
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didFailToConnect peripheral: CBPeripheral,
                                    error: Error?) {
        Task { @MainActor in
            self.addLog("Ошибка подключения: \(error?.localizedDescription ?? "неизвестная ошибка")")
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: Error?) {
        Task { @MainActor in
            self.connectedPeripheral = nil
            self.connectedName = nil
            self.discoveredServices = []
            self.addLog("Соединение разорвано.")
        }
    }
}

extension BluetoothManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverServices error: Error?) {
        let services = peripheral.services ?? []
        let ids = services.map { $0.uuid.uuidString }
        Task { @MainActor in
            self.discoveredServices = ids
            if let error {
                self.addLog("Ошибка чтения служб: \(error.localizedDescription)")
            } else {
                self.addLog("Обнаружено служб: \(ids.count)")
            }
        }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverCharacteristicsFor service: CBService,
                                error: Error?) {
        let chars = service.characteristics ?? []
        let lines = chars.map {
            "\($0.uuid.uuidString) [\($0.properties.description)]"
        }
        Task { @MainActor in
            for line in lines {
                self.addLog("Характеристика: \(line)")
            }
        }
    }
}

private extension CBCharacteristicProperties {
    var description: String {
        var values: [String] = []
        if contains(.read) { values.append("read") }
        if contains(.write) { values.append("write") }
        if contains(.writeWithoutResponse) { values.append("writeWithoutResponse") }
        if contains(.notify) { values.append("notify") }
        if contains(.indicate) { values.append("indicate") }
        return values.isEmpty ? "—" : values.joined(separator: ", ")
    }
}
