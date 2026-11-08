import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var bluetooth: BluetoothManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    VStack(alignment: .leading, spacing: 10) {
                        Text("ПОДКЛЮЧЕНИЕ")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)

                        HStack {
                            Circle()
                                .fill(bluetooth.connectedName == nil ? .orange : .green)
                                .frame(width: 9, height: 9)
                            Text(bluetooth.connectedName ?? bluetooth.stateText)
                                .font(.subheadline)
                            Spacer()
                            if bluetooth.connectedName != nil {
                                Button("Отключить") { bluetooth.disconnect() }
                                    .font(.caption)
                            }
                        }

                        HStack {
                            Button {
                                bluetooth.startScan()
                            } label: {
                                Label("Сканировать", systemImage: "dot.radiowaves.left.and.right")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Стоп") { bluetooth.stopScan() }
                                .buttonStyle(.bordered)
                        }
                    }
                    .padding()
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("НАЙДЕННЫЕ УСТРОЙСТВА")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)

                        if bluetooth.devices.isEmpty {
                            Text("Нажми «Сканировать». Временно отключи OM7P от DJI Mimo, если он уже подключён.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        ForEach(bluetooth.devices) { device in
                            Button {
                                bluetooth.connect(device)
                            } label: {
                                HStack {
                                    Image(systemName: "gyroscope")
                                    VStack(alignment: .leading) {
                                        Text(device.name).foregroundStyle(.primary)
                                        Text("Сигнал: \(device.rssi) dBm")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.secondary)
                                }
                                .padding(12)
                                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("BLE-СЛУЖБЫ")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        if bluetooth.discoveredServices.isEmpty {
                            Text("Пока не получены.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(bluetooth.discoveredServices, id: \.self) { uuid in
                                Text(uuid)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding()
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("ЖУРНАЛ")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        ForEach(Array(bluetooth.log.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding()
            }
            .background(Color(red: 0.035, green: 0.045, blue: 0.065))
            .navigationBarHidden(true)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("OM")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(.cyan)
            Text("MOTION STUDIO")
                .font(.system(size: 29, weight: .bold, design: .rounded))
            Text("Bluetooth diagnostics · Prototype 0.1")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }
}
