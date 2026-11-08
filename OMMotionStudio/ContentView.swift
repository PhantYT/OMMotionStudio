import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var bluetooth: BluetoothManager
    @EnvironmentObject private var camera: CameraManager
    @StateObject private var motion = MotionEngine()

    private var maxMotorSpeed: Int {
        max(120, min(1800, Int(1200 * motion.sensitivity)))
    }

    var body: some View {
        TabView {
            controlScreen.tabItem { Label("Управление", systemImage: "gamecontroller") }
            motionScreen.tabItem { Label("Движение", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
            cameraScreen.tabItem { Label("Камера", systemImage: "video") }
            bluetoothScreen.tabItem { Label("Bluetooth", systemImage: "dot.radiowaves.left.and.right") }
        }
        .tint(.cyan)
        .preferredColorScheme(.dark)
        .onChange(of: motion.pan) { _, value in
            guard motion.isPlaying else { return }
            bluetooth.sendJoystick(yaw: value, pitch: motion.tilt, maxSpeed: maxMotorSpeed)
        }
        .onChange(of: motion.tilt) { _, value in
            guard motion.isPlaying else { return }
            bluetooth.sendJoystick(yaw: motion.pan, pitch: value, maxSpeed: maxMotorSpeed)
        }
        .onChange(of: motion.isPlaying) { _, playing in
            if !playing { bluetooth.stopGimbal() }
        }
    }

    private var controlScreen: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header(title: "Управление", subtitle: "Физическое управление DJI Osmo Mobile 7P")

                    HStack(spacing: 12) {
                        statusCard("BLUETOOTH", bluetooth.connectedName ?? "Не подключён", active: bluetooth.connectedName != nil)
                        statusCard("ПРОТОКОЛ", bluetooth.canControl ? "OM7P готов" : bluetooth.protocolStatus, active: bluetooth.canControl)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("ДЖОЙСТИК")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("PAN / TILT")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                        JoystickView { x, y in
                            motion.setJoystick(pan: x, tilt: y)
                            if abs(x) < 0.01 && abs(y) < 0.01 {
                                bluetooth.stopGimbal()
                            } else {
                                bluetooth.sendJoystick(yaw: x, pitch: y, maxSpeed: maxMotorSpeed)
                            }
                        }
                        .frame(height: 265)
                        HStack {
                            valueCard("PAN", value: motion.pan)
                            valueCard("TILT", value: motion.tilt)
                        }
                    }
                    .padding()
                    .background(Color.white.opacity(0.045))
                    .clipShape(RoundedRectangle(cornerRadius: 22))

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Скорость моторов")
                            Spacer()
                            Text("\(maxMotorSpeed)").foregroundStyle(.cyan).monospacedDigit()
                        }
                        Slider(value: $motion.sensitivity, in: 0.1...1.5)
                            .tint(.cyan)
                    }
                    .padding()
                    .background(Color.white.opacity(0.045))
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                    HStack(spacing: 10) {
                        actionButton("ЦЕНТР", icon: "scope") { bluetooth.recenter() }
                        actionButton("LOCK", icon: "lock.fill") { bluetooth.setMode("lock") }
                        actionButton("FOLLOW", icon: "figure.walk") { bluetooth.setMode("follow") }
                        actionButton("FPV", icon: "view.3d") { bluetooth.setMode("fpv") }
                    }
                    .disabled(!bluetooth.canControl)

                    Text(bluetooth.protocolStatus)
                        .font(.caption)
                        .foregroundStyle(bluetooth.canControl ? .green : .orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
            .background(Color.black)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var motionScreen: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header(title: "Motion Studio", subtitle: "Запись и воспроизведение траекторий")

                    HStack {
                        metricCard("KEYFRAMES", value: "\(motion.keyframes.count)", icon: "diamond")
                        metricCard("ДЛИТЕЛЬНОСТЬ", value: "\(Int(motion.duration)) сек", icon: "clock")
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(timeString(motion.playhead)).monospacedDigit()
                            Spacer()
                            Text(timeString(motion.duration)).monospacedDigit()
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Slider(value: Binding(get: { motion.playhead }, set: { motion.seek($0) }), in: 0...max(1, motion.duration))
                            .tint(.cyan)
                        HStack(spacing: 10) {
                            Button { motion.stop(); bluetooth.stopGimbal() } label: {
                                Image(systemName: "stop.fill").frame(width: 48, height: 48)
                                    .background(Color.white.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            Button { motion.isPlaying ? motion.pause() : motion.play() } label: {
                                Label(motion.isPlaying ? "Пауза" : "Воспроизвести", systemImage: motion.isPlaying ? "pause.fill" : "play.fill")
                                    .frame(maxWidth: .infinity).frame(height: 48)
                                    .background(.cyan).foregroundStyle(.black).clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            Button { motion.addKeyframe() } label: {
                                Image(systemName: "plus").frame(width: 48, height: 48)
                                    .background(Color.white.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .buttonStyle(.plain)
                        Text("Для воспроизведения нужно минимум две точки. Стабилизатор должен быть подключён.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding().background(Color.white.opacity(0.045)).clipShape(RoundedRectangle(cornerRadius: 20))

                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Text("Длительность"); Spacer(); Text("\(Int(motion.duration)) сек").foregroundStyle(.cyan) }
                        Slider(value: Binding(get: { motion.duration }, set: { motion.updateDuration($0) }), in: 1...120, step: 1).tint(.cyan)
                        HStack { Text("Плавность"); Spacer(); Text("\(Int(motion.easing * 100))%").foregroundStyle(.cyan) }
                        Slider(value: $motion.easing, in: 0...1).tint(.cyan)
                    }
                    .padding().background(Color.white.opacity(0.045)).clipShape(RoundedRectangle(cornerRadius: 20))

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("KEYFRAMES").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                            Spacer()
                            Button("Очистить", role: .destructive) { motion.clearKeyframes() }
                                .font(.caption)
                        }
                        if motion.keyframes.isEmpty {
                            Text("Пока нет ключевых кадров").foregroundStyle(.secondary)
                        } else {
                            ForEach(motion.keyframes) { frame in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("\(timeString(frame.time))")
                                            .fontWeight(.semibold)
                                        Text("PAN \(Int(frame.pan * 100))% · TILT \(Int(frame.tilt * 100))%")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button { motion.selectKeyframe(frame) } label: { Image(systemName: "arrow.right.circle").foregroundStyle(.cyan) }
                                    Button(role: .destructive) { motion.removeKeyframe(frame) } label: { Image(systemName: "trash") }
                                }
                                .padding(10).background(Color.white.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                    .padding().background(Color.white.opacity(0.045)).clipShape(RoundedRectangle(cornerRadius: 20))

                    Button { motion.saveProject() } label: {
                        Label("Сохранить проект", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity).padding()
                            .background(Color.white.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            }
            .background(Color.black)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var cameraScreen: some View {
        NavigationStack {
            VStack(spacing: 16) {
                header(title: "Camera", subtitle: "Камера iPhone").padding(.horizontal)
                ZStack {
                    RoundedRectangle(cornerRadius: 20).fill(Color.white.opacity(0.05))
                    if camera.isReady {
                        CameraPreview(session: camera.session).clipShape(RoundedRectangle(cornerRadius: 20))
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "camera.fill").font(.system(size: 42)).foregroundStyle(.secondary)
                            Text(camera.status).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity).aspectRatio(9.0 / 16.0, contentMode: .fit).padding(.horizontal)
                Text(camera.status).font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button { camera.start() } label: {
                        Label("Запустить", systemImage: "camera").frame(maxWidth: .infinity).padding()
                            .background(Color.white.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    Button { camera.isRecording ? camera.stopRecording() : camera.record() } label: {
                        Label(camera.isRecording ? "Стоп" : "Запись", systemImage: camera.isRecording ? "stop.fill" : "record.circle")
                            .frame(maxWidth: .infinity).padding()
                            .background(camera.isRecording ? Color.red : Color.cyan)
                            .foregroundStyle(camera.isRecording ? .white : .black)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(!camera.isReady)
                }
                .buttonStyle(.plain).padding(.horizontal)
                Spacer()
            }
            .padding(.top).background(Color.black).toolbar(.hidden, for: .navigationBar)
            .onAppear { camera.start() }
            .onDisappear { if !camera.isRecording { camera.stopSession() } }
        }
    }

    private var bluetoothScreen: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(title: "Bluetooth", subtitle: "BLE OM7P · FFF0 / FFF4 / FFF5")
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(bluetooth.connectedName ?? bluetooth.stateText).font(.subheadline)
                            Text(bluetooth.protocolStatus).font(.caption).foregroundStyle(bluetooth.canControl ? .green : .orange)
                        }
                        Spacer()
                        if bluetooth.connectedName != nil {
                            Button("Отключить") { bluetooth.disconnect() }.foregroundStyle(.red)
                        }
                    }
                    .padding().background(Color.white.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius: 14))
                    HStack(spacing: 10) {
                        Button { bluetooth.startScan() } label: {
                            Label("Сканировать", systemImage: "antenna.radiowaves.left.and.right")
                                .frame(maxWidth: .infinity).padding().background(.cyan).foregroundStyle(.black)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        Button { bluetooth.stopScan() } label: {
                            Image(systemName: "stop.fill").frame(width: 48, height: 48)
                                .background(Color.white.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .buttonStyle(.plain)

                    sectionTitle("Найденные устройства")
                    if bluetooth.devices.isEmpty { Text("Устройства пока не найдены").foregroundStyle(.secondary) }
                    ForEach(bluetooth.devices) { device in
                        Button { bluetooth.connect(device) } label: {
                            HStack {
                                Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(.cyan)
                                VStack(alignment: .leading) {
                                    Text(device.name).foregroundStyle(.primary)
                                    Text(device.id.uuidString).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(device.rssi) dBm").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            .padding().background(Color.white.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }

                    sectionTitle("Службы и характеристики")
                    if bluetooth.services.isEmpty { Text("Подключись к устройству, чтобы увидеть GATT.").foregroundStyle(.secondary) }
                    ForEach(bluetooth.services) { service in
                        VStack(alignment: .leading, spacing: 10) {
                            Text("SERVICE  \(service.id)").font(.caption.weight(.bold)).foregroundStyle(.cyan)
                            ForEach(service.characteristics) { characteristic in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(characteristic.id).font(.caption.monospaced())
                                    Text(characteristic.properties).font(.caption2).foregroundStyle(.secondary)
                                    Text(characteristic.value).font(.caption.monospaced()).textSelection(.enabled)
                                    if characteristic.isNotifying { Text("NOTIFY ACTIVE").font(.caption2.weight(.bold)).foregroundStyle(.green) }
                                }
                                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.white.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        .padding().background(Color.white.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    HStack {
                        sectionTitle("Журнал")
                        Spacer()
                        Button("Очистить") { bluetooth.clearLog() }.font(.caption)
                    }
                    ForEach(Array(bluetooth.log.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    }
                }
                .padding()
            }
            .background(Color.black).toolbar(.hidden, for: .navigationBar)
        }
    }

    private func header(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("OM MOTION STUDIO").font(.caption.weight(.bold)).tracking(2).foregroundStyle(.cyan)
            Text(title).font(.system(size: 30, weight: .bold))
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased()).font(.caption.weight(.bold)).tracking(1).foregroundStyle(.secondary)
    }

    private func statusCard(_ title: String, _ value: String, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            HStack(spacing: 7) {
                Circle().fill(active ? .green : .orange).frame(width: 7, height: 7)
                Text(value).font(.caption.weight(.semibold)).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding()
        .background(Color.white.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func valueCard(_ title: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            Text("\(Int(value * 100))%").font(.title3.monospacedDigit().weight(.bold)).foregroundStyle(.cyan)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding()
        .background(Color.white.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func metricCard(_ title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).foregroundStyle(.cyan)
            Text(value).font(.title2.weight(.bold)).monospacedDigit()
            Text(title).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding()
        .background(Color.white.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                Text(title).font(.system(size: 10, weight: .bold))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(Color.white.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func timeString(_ value: Double) -> String {
        let seconds = max(0, Int(value))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

struct JoystickView: View {
    var onChange: (Double, Double) -> Void
    @State private var offset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let limit = max(30, side * 0.34)
            ZStack {
                Circle().fill(Color.white.opacity(0.035)).overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
                Circle().stroke(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [5, 6])).padding(side * 0.2)
                Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                Circle().fill(.cyan.opacity(0.15)).frame(width: 78, height: 78)
                    .overlay(Circle().stroke(.cyan.opacity(0.6), lineWidth: 2))
                    .overlay(Image(systemName: "move").font(.system(size: 24, weight: .semibold)).foregroundStyle(.cyan))
                    .offset(offset).shadow(color: .cyan.opacity(0.2), radius: 12)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let x = value.translation.width
                                let y = value.translation.height
                                let length = sqrt(x * x + y * y)
                                let scale = length > limit ? limit / length : 1
                                offset = CGSize(width: x * scale, height: y * scale)
                                onChange(Double(offset.width / limit), Double(-offset.height / limit))
                            }
                            .onEnded { _ in
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.65)) { offset = .zero }
                                onChange(0, 0)
                            }
                    )
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
