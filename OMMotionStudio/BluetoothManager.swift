import Combine
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
    @Published private(set) var protocolStatus = "Ожидание подключения"
    @Published private(set) var isProtocolReady = false
    @Published private(set) var battery: Int?

    private let serviceUUID = "FFF0"
    private let notifyUUID = "FFF4"
    private let writeUUID = "FFF5"

    private var central: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var characteristics: [String: CBCharacteristic] = [:]
    private let parser = DumlParser()
    private var sequence: UInt16 = 1

    private var writeChunks: [Data] = []
    private var pendingJoystick: (yaw: Double, pitch: Double, maxSpeed: Int)?
    private var joystickWorkItem: DispatchWorkItem?
    private var handshakeWorkItem: DispatchWorkItem?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    var canControl: Bool {
        isProtocolReady
            && connectedPeripheral != nil
            && characteristics[writeUUID] != nil
            && characteristics[notifyUUID]?.isNotifying == true
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
        protocolStatus = "Подключение к OM 7P..."
        isProtocolReady = false
        appendLog("Подключение к \(device.name)...")
        central.connect(device.peripheral, options: nil)
    }

    func disconnect() {
        guard let peripheral = connectedPeripheral else { return }
        stopGimbal()
        central.cancelPeripheralConnection(peripheral)
    }

    func clearLog() {
        log.removeAll()
    }

    // MARK: - Физическое управление OM7P

    func sendJoystick(yaw: Double, pitch: Double, maxSpeed: Int = 1200) {
        guard canControl else { return }

        pendingJoystick = (
            yaw: max(-1, min(1, yaw)),
            pitch: max(-1, min(1, pitch)),
            maxSpeed: max(80, min(1800, maxSpeed))
        )

        guard joystickWorkItem == nil else { return }

        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.joystickWorkItem = nil

            guard let axes = self.pendingJoystick else { return }
            self.pendingJoystick = nil
            guard self.canControl else { return }

            // В OM SPEED положительный pitch — движение вниз, поэтому ось Y инвертируется.
            let yawSpeed = DumlCodec.stickSpeed(axes.yaw, maximum: axes.maxSpeed)
            let pitchSpeed = DumlCodec.stickSpeed(-axes.pitch, maximum: axes.maxSpeed)

            let packet = DumlCodec.buildSpeedRotate(
                yaw: yawSpeed,
                pitch: pitchSpeed,
                roll: 0,
                duration: 10,
                sequence: self.nextSequence()
            )
            self.writePacket(packet, label: "SPEED pan=\(yawSpeed) tilt=\(pitchSpeed)")
        }

        joystickWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: item)
    }

    func stopGimbal() {
        joystickWorkItem?.cancel()
        joystickWorkItem = nil
        pendingJoystick = nil
        guard canControl else { return }

        let speedStop = DumlCodec.buildSpeedRotate(
            yaw: 0,
            pitch: 0,
            roll: 0,
            duration: 10,
            sequence: nextSequence()
        )
        writePacket(speedStop, label: "SPEED STOP")

        let pwmStop = DumlCodec.buildPWM(
            yaw: DumlCodec.pwmCenter,
            pitch: DumlCodec.pwmCenter,
            roll: DumlCodec.pwmCenter,
            sequence: nextSequence()
        )
        writePacket(pwmStop, label: "PWM CENTER")
    }

    func recenter() {
        guard canControl else {
            appendLog("Recenter недоступен: DUML ещё не готов")
            return
        }

        stopGimbal()
        let packet = DumlCodec.buildAbsoluteRotate(
            yaw: 0,
            pitch: 0,
            roll: 0,
            duration: 20,
            sequence: nextSequence()
        )
        writePacket(packet, label: "RECENTER")
    }

    func setMode(_ mode: String) {
        let values: [String: UInt8] = ["lock": 0, "follow": 1, "fpv": 2]
        guard canControl, let value = values[mode] else {
            appendLog("Режим недоступен: \(mode)")
            return
        }

        writePacket(
            DumlCodec.buildSetMode(value, sequence: nextSequence()),
            label: "MODE \(mode.uppercased())"
        )
    }

    // MARK: - Инициализация и обмен DUML

    private func beginProtocolHandshake() {
        guard !isProtocolReady,
              connectedPeripheral != nil,
              characteristics[writeUUID] != nil,
              characteristics[notifyUUID]?.isNotifying == true
        else {
            return
        }

        protocolStatus = "Опрашиваем положение подвеса..."
        appendLog("OM7P GATT найден: FFF0 / FFF4 / FFF5")

        let probe = DumlCodec.buildPositionRequest(sequence: nextSequence())
        writePacket(probe, label: "GET_GIMBAL_POSITION 0x04/0x02")

        let timeout = DispatchWorkItem { [weak self] in
            guard let self, !self.isProtocolReady, self.connectedPeripheral != nil else {
                return
            }

            // В исходном OM7P-драйвере команды движения отправляются сразу после подписки FFF4.
            // Поэтому тайм-аут диагностического опроса не блокирует проверенный SPEED-режим.
            self.isProtocolReady = true
            self.protocolStatus = "FFF4/FFF5 подтверждены; ответа GET_POS нет"
            self.appendLog("Тайм-аут GET_POS. Ручной OM7P SPEED разрешён по подтверждённому профилю.")
        }

        handshakeWorkItem?.cancel()
        handshakeWorkItem = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: timeout)
    }

    private func handleIncoming(_ data: Data, characteristic: CBCharacteristic) {
        let packets = parser.feed(data)

        if packets.isEmpty {
            appendLog("RX \(shortUUID(characteristic.uuid)): \(hex(data))")
        }

        for packet in packets {
            handshakeWorkItem?.cancel()
            handshakeWorkItem = nil

            if !isProtocolReady {
                isProtocolReady = true
                protocolStatus = "DUML подтверждён: \(packet.summary)"
                appendLog("Ответ стабилизатора получен. Управление разблокировано.")
            } else {
                protocolStatus = "DUML активен · \(packet.summary)"
            }

            if packet.commandSet == 0x05,
               packet.command == 0x06,
               let first = packet.payload.first {
                battery = Int(first)
            }

            appendLog("RX \(shortUUID(characteristic.uuid)) \(packet.summary)")
        }
    }

    private func writePacket(_ packet: Data, label: String) {
        guard let peripheral = connectedPeripheral,
              let characteristic = characteristics[writeUUID] else {
            appendLog("TX отменён: FFF5 недоступна")
            return
        }

        guard characteristic.properties.contains(.writeWithoutResponse) else {
            appendLog("TX отменён: FFF5 не поддерживает Write Without Response")
            return
        }

        let maximum = max(1, peripheral.maximumWriteValueLength(for: .withoutResponse))
        var offset = 0
        while offset < packet.count {
            let end = min(offset + maximum, packet.count)
            writeChunks.append(packet.subdata(in: offset..<end))
            offset = end
        }

        appendLog("TX FFF5 \(label): \(hex(packet))")
        drainWriteQueue(peripheral: peripheral, characteristic: characteristic)
    }

    private func drainWriteQueue(
        peripheral: CBPeripheral,
        characteristic: CBCharacteristic
    ) {
        while !writeChunks.isEmpty && peripheral.canSendWriteWithoutResponse {
            let chunk = writeChunks.removeFirst()
            peripheral.writeValue(chunk, for: characteristic, type: .withoutResponse)
        }
    }

    private func nextSequence() -> UInt16 {
        let value = sequence
        sequence = sequence &+ 1
        if sequence == 0 { sequence = 1 }
        return value
    }

    private func shortUUID(_ uuid: CBUUID) -> String {
        let value = uuid.uuidString.uppercased()
        if value == "0000FFF0-0000-1000-8000-00805F9B34FB" { return "FFF0" }
        if value == "0000FFF4-0000-1000-8000-00805F9B34FB" { return "FFF4" }
        if value == "0000FFF5-0000-1000-8000-00805F9B34FB" { return "FFF5" }
        return value
    }

    private func appendLog(_ message: String) {
        log.insert(
            "[\(Date().formatted(date: .omitted, time: .standard))] \(message)",
            at: 0
        )
        if log.count > 250 {
            log.removeLast(log.count - 250)
        }
    }

    private func propertiesText(_ properties: CBCharacteristicProperties) -> String {
        var result: [String] = []
        if properties.contains(.read) { result.append("READ") }
        if properties.contains(.write) { result.append("WRITE") }
        if properties.contains(.writeWithoutResponse) { result.append("WRITE WITHOUT RESPONSE") }
        if properties.contains(.notify) { result.append("NOTIFY") }
        if properties.contains(.indicate) { result.append("INDICATE") }
        return result.isEmpty ? "UNKNOWN" : result.joined(separator: ", ")
    }

    private func hex(_ data: Data?) -> String {
        guard let data, !data.isEmpty else { return "Нет данных" }
        return data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private func updateCharacteristic(_ characteristic: CBCharacteristic) {
        let serviceID = characteristic.service?.uuid.uuidString ?? ""
        guard let serviceIndex = services.firstIndex(where: { $0.id == serviceID }) else {
            return
        }

        let info = GATTCharacteristicInfo(
            id: characteristic.uuid.uuidString,
            properties: propertiesText(characteristic.properties),
            isNotifying: characteristic.isNotifying,
            value: hex(characteristic.value)
        )

        if let index = services[serviceIndex].characteristics.firstIndex(where: { $0.id == info.id }) {
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
            case .poweredOn: self.stateText = "Bluetooth включён"
            case .poweredOff: self.stateText = "Bluetooth выключен"
            case .unauthorized: self.stateText = "Нет разрешения Bluetooth"
            case .unsupported: self.stateText = "Bluetooth не поддерживается"
            case .resetting: self.stateText = "Bluetooth перезапускается"
            case .unknown: self.stateText = "Состояние неизвестно"
            @unknown default: self.stateText = "Неизвестное состояние"
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
                    GimbalDevice(id: id, name: name, rssi: signal, peripheral: peripheral)
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
            self.characteristics.removeAll()
            self.writeChunks.removeAll()
            self.parser.reset()
            self.isProtocolReady = false
            self.protocolStatus = "Поиск FFF0 / FFF4 / FFF5..."
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
            self.protocolStatus = "Ошибка подключения"
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
            self.handshakeWorkItem?.cancel()
            self.joystickWorkItem?.cancel()
            self.handshakeWorkItem = nil
            self.joystickWorkItem = nil
            self.pendingJoystick = nil
            self.connectedPeripheral = nil
            self.connectedName = nil
            self.characteristics.removeAll()
            self.writeChunks.removeAll()
            self.parser.reset()
            self.isProtocolReady = false
            self.protocolStatus = "Соединение разорвано"
            self.services.removeAll()
            self.appendLog("Соединение разорвано\(message.map { ": \($0)" } ?? "")")
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
                GATTServiceInfo(id: $0.uuid.uuidString, characteristics: [])
            }

            if !found.contains(where: {
                let uuid = $0.uuid.uuidString.uppercased()
                return uuid == "FFF0" || uuid == "0000FFF0-0000-1000-8000-00805F9B34FB"
            }) {
                self.protocolStatus = "Служба FFF0 не найдена"
                self.appendLog("Устройство не объявило стандартную OM BLE-службу FFF0")
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
        let found = service.characteristics ?? []
        let serviceID = service.uuid.uuidString

        Task { @MainActor in
            if let error {
                self.appendLog("Ошибка характеристик: \(error.localizedDescription)")
            }
            self.appendLog("Служба \(serviceID): \(found.count) характеристик")

            for characteristic in found {
                let short = self.shortUUID(characteristic.uuid)
                if short == self.writeUUID || short == self.notifyUUID {
                    self.characteristics[short] = characteristic
                }
                self.updateCharacteristic(characteristic)
                self.appendLog(
                    "Характеристика: \(characteristic.uuid.uuidString) [\(self.propertiesText(characteristic.properties))]"
                )
            }

            if self.characteristics[self.writeUUID] == nil {
                self.protocolStatus = "FFF5 для записи не найдена"
            } else if self.characteristics[self.notifyUUID] == nil {
                self.protocolStatus = "FFF4 для телеметрии не найдена"
            }

            if self.characteristics[self.notifyUUID]?.isNotifying == true {
                self.beginProtocolHandshake()
            }
        }

        for characteristic in found {
            if characteristic.properties.contains(.read) {
                peripheral.readValue(for: characteristic)
            }

            let short = characteristic.uuid.uuidString.uppercased()
            let isOsmoNotify = short == "FFF4"
                || short == "FFF5"
                || short == "0000FFF4-0000-1000-8000-00805F9B34FB"
                || short == "0000FFF5-0000-1000-8000-00805F9B34FB"

            if isOsmoNotify
                && (characteristic.properties.contains(.notify)
                    || characteristic.properties.contains(.indicate)) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        let value = characteristic.value
        let message = error?.localizedDescription
        Task { @MainActor in
            if let message {
                self.appendLog("Ошибка чтения \(characteristic.uuid.uuidString): \(message)")
            } else if let value {
                self.handleIncoming(value, characteristic: characteristic)
            }
            self.updateCharacteristic(characteristic)
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        let enabled = characteristic.isNotifying
        let message = error?.localizedDescription
        Task { @MainActor in
            if let message {
                self.appendLog("Ошибка Notify \(characteristic.uuid.uuidString): \(message)")
            } else {
                self.appendLog("Notify \(characteristic.uuid.uuidString): \(enabled ? "включён" : "выключен")")
            }

            self.updateCharacteristic(characteristic)
            if self.shortUUID(characteristic.uuid) == self.notifyUUID {
                if enabled {
                    self.beginProtocolHandshake()
                } else {
                    self.isProtocolReady = false
                    self.protocolStatus = "Нет подписки на FFF4"
                }
            }
        }
    }

    nonisolated func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        Task { @MainActor in
            guard let characteristic = self.characteristics[self.writeUUID],
                  peripheral === self.connectedPeripheral else {
                return
            }
            self.drainWriteQueue(peripheral: peripheral, characteristic: characteristic)
        }
    }
}
