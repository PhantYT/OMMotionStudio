import Foundation
import SwiftUI
import Combine

struct MotionKeyframe: Identifiable, Codable, Equatable {
    var id: UUID
    var time: Double
    var pan: Double
    var tilt: Double

    init(id: UUID = UUID(), time: Double, pan: Double, tilt: Double) {
        self.id = id
        self.time = time
        self.pan = pan
        self.tilt = tilt
    }
}

@MainActor
final class MotionEngine: ObservableObject {
    @Published var joystickX: Double = 0
    @Published var joystickY: Double = 0
    @Published var sensitivity: Double = 1.0
    @Published var pan: Double = 0
    @Published var tilt: Double = 0
    @Published var duration: Double = 10
    @Published var playhead: Double = 0
    @Published var isPlaying = false
    @Published var keyframes: [MotionKeyframe] = []
    @Published var easing: Double = 0.5
    @Published var controlPoint1X: Double = 0.25
    @Published var controlPoint1Y: Double = 0.1
    @Published var controlPoint2X: Double = 0.75
    @Published var controlPoint2Y: Double = 0.9

    private var playbackTimer: Timer?
    private var lastPlaybackDate: Date?
    private let storageKey = "OMMotionStudio.Keyframes"
    private let projectStorageKey = "OMMotionStudio.Project"

    init() { loadKeyframes() }

    // Сохраняем координаты стика как значения осей, а не накапливаем их.
    func setJoystick(pan: Double, tilt: Double) {
        joystickX = max(-1, min(1, pan))
        joystickY = max(-1, min(1, tilt))
        self.pan = joystickX
        self.tilt = joystickY
    }

    func moveJoystick(x: Double, y: Double) { setJoystick(pan: x, tilt: y) }

    func releaseJoystick() {
        joystickX = 0
        joystickY = 0
    }

    func resetPosition() {
        pan = 0
        tilt = 0
        joystickX = 0
        joystickY = 0
    }

    func addKeyframe() {
        let frame = MotionKeyframe(time: playhead, pan: pan, tilt: tilt)
        keyframes.removeAll { abs($0.time - playhead) < 0.01 }
        keyframes.append(frame)
        keyframes.sort { $0.time < $1.time }
        saveKeyframes()
    }

    func removeKeyframe(_ frame: MotionKeyframe) {
        keyframes.removeAll { $0.id == frame.id }
        saveKeyframes()
    }

    func deleteKeyframe(_ frame: MotionKeyframe) { removeKeyframe(frame) }

    func clearKeyframes() {
        keyframes.removeAll()
        playhead = 0
        saveKeyframes()
    }

    func selectKeyframe(_ frame: MotionKeyframe) {
        seek(frame.time)
        pan = frame.pan
        tilt = frame.tilt
    }

    func saveProject() {
        saveKeyframes()
        do {
            let data = try JSONEncoder().encode(keyframes)
            UserDefaults.standard.set(data, forKey: projectStorageKey)
        } catch {
            print("Ошибка сохранения проекта: \(error)")
        }
    }

    func saveKeyframes() {
        do {
            let data = try JSONEncoder().encode(keyframes)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("Ошибка сохранения Keyframes: \(error)")
        }
    }

    func loadKeyframes() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            keyframes = try JSONDecoder().decode([MotionKeyframe].self, from: data)
            keyframes.sort { $0.time < $1.time }
        } catch {
            print("Ошибка загрузки Keyframes: \(error)")
        }
    }

    func seek(_ value: Double) {
        playhead = max(0, min(duration, value))
        updatePosition(at: playhead)
    }

    func setPlayhead(_ value: Double) { seek(value) }

    func updateDuration(_ value: Double) {
        duration = max(1, min(120, value))
        playhead = min(playhead, duration)
    }

    func setDuration(_ value: Double) { updateDuration(value) }

    func play() {
        guard !isPlaying, keyframes.count >= 2 else { return }
        if playhead >= duration { seek(0) }
        isPlaying = true
        lastPlaybackDate = Date()
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.playbackStep() }
        }
    }

    func pause() {
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
        lastPlaybackDate = nil
    }

    func stop() {
        pause()
        seek(0)
    }

    private func playbackStep() {
        guard isPlaying else { return }
        let now = Date()
        guard let previous = lastPlaybackDate else { lastPlaybackDate = now; return }
        lastPlaybackDate = now
        playhead += now.timeIntervalSince(previous)
        if playhead >= duration {
            playhead = duration
            updatePosition(at: playhead)
            pause()
        } else {
            updatePosition(at: playhead)
        }
    }

    func updatePosition(at time: Double) {
        guard !keyframes.isEmpty else { return }
        let frames = keyframes.sorted { $0.time < $1.time }
        guard let first = frames.first, let last = frames.last else { return }
        if time <= first.time { pan = first.pan; tilt = first.tilt; return }
        if time >= last.time { pan = last.pan; tilt = last.tilt; return }

        for index in 0..<(frames.count - 1) {
            let start = frames[index]
            let end = frames[index + 1]
            if time >= start.time && time <= end.time {
                let segmentDuration = end.time - start.time
                guard segmentDuration > 0 else { continue }
                let progress = bezierProgress((time - start.time) / segmentDuration)
                pan = start.pan + (end.pan - start.pan) * progress
                tilt = start.tilt + (end.tilt - start.tilt) * progress
                return
            }
        }
    }

    private func bezierProgress(_ value: Double) -> Double {
        let t = max(0, min(1, value))
        let smooth = t * t * (3 - 2 * t)
        let strength = max(0, min(1, easing))
        return t * (1 - strength) + smooth * strength
    }

    deinit { playbackTimer?.invalidate() }
}
