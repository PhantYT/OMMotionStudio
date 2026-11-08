
import Foundation
import SwiftUI
import Combine

struct MotionKeyframe: Identifiable, Codable, Equatable {
    var id: UUID
    var time: Double
    var pan: Double
    var tilt: Double

    init(
        id: UUID = UUID(),
        time: Double,
        pan: Double,
        tilt: Double
    ) {
        self.id = id
        self.time = time
        self.pan = pan
        self.tilt = tilt
    }
}

@MainActor
final class MotionEngine: ObservableObject {

    // MARK: - Джойстик

    @Published var joystickX: Double = 0
    @Published var joystickY: Double = 0
    @Published var sensitivity: Double = 1.0

    // MARK: - Положение

    @Published var pan: Double = 0
    @Published var tilt: Double = 0

    // MARK: - Timeline

    @Published var duration: Double = 10
    @Published var playhead: Double = 0
    @Published var isPlaying = false

    // MARK: - Keyframes

    @Published var keyframes: [MotionKeyframe] = []

    // MARK: - Анимация

    @Published var easing: Double = 0.5

    @Published var controlPoint1X: Double = 0.25
    @Published var controlPoint1Y: Double = 0.1
    @Published var controlPoint2X: Double = 0.75
    @Published var controlPoint2Y: Double = 0.9

    private var playbackTimer: Timer?
    private var lastPlaybackDate: Date?

    private let storageKey = "OMMotionStudio.Keyframes"
    private let projectStorageKey = "OMMotionStudio.Project"

    // MARK: - Init

    init() {
        loadKeyframes()
    }

    // MARK: - Джойстик

    func setJoystick(pan: Double, tilt: Double) {
        joystickX = max(-1, min(1, pan))
        joystickY = max(-1, min(1, tilt))

        self.pan += joystickX * sensitivity
        self.tilt += joystickY * sensitivity

        self.pan = max(-1, min(1, self.pan))
        self.tilt = max(-1, min(1, self.tilt))
    }

    func moveJoystick(x: Double, y: Double) {
        setJoystick(pan: x, tilt: y)
    }

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

    // MARK: - Keyframes

    func addKeyframe() {
        let frame = MotionKeyframe(
            time: playhead,
            pan: pan,
            tilt: tilt
        )

        keyframes.removeAll {
            abs($0.time - playhead) < 0.01
        }

        keyframes.append(frame)

        keyframes.sort {
            $0.time < $1.time
        }

        saveKeyframes()
    }

    func removeKeyframe(_ frame: MotionKeyframe) {
        keyframes.removeAll {
            $0.id == frame.id
        }

        saveKeyframes()
    }

    func deleteKeyframe(_ frame: MotionKeyframe) {
        removeKeyframe(frame)
    }

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

    // MARK: - Сохранение проекта

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
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return
        }

        do {
            keyframes = try JSONDecoder().decode(
                [MotionKeyframe].self,
                from: data
            )

            keyframes.sort {
                $0.time < $1.time
            }
        } catch {
            print("Ошибка загрузки Keyframes: \(error)")
        }
    }

    // MARK: - Timeline

    func seek(_ value: Double) {
        playhead = max(0, min(duration, value))
        updatePosition(at: playhead)
    }

    func setPlayhead(_ value: Double) {
        seek(value)
    }

    func updateDuration(_ value: Double) {
        duration = max(1, min(120, value))
        playhead = min(playhead, duration)
    }

    func setDuration(_ value: Double) {
        updateDuration(value)
    }

    // MARK: - Воспроизведение

    func play() {
        guard !isPlaying else {
            return
        }

        guard keyframes.count >= 2 else {
            print("Для воспроизведения нужно минимум 2 Keyframes")
            return
        }

        if playhead >= duration {
            seek(0)
        }

        isPlaying = true
        lastPlaybackDate = Date()

        playbackTimer?.invalidate()

        playbackTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0 / 60.0,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.playbackStep()
            }
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
        guard isPlaying else {
            return
        }

        let now = Date()

        guard let previousDate = lastPlaybackDate else {
            lastPlaybackDate = now
            return
        }

        let delta = now.timeIntervalSince(previousDate)
        lastPlaybackDate = now

        playhead += delta

        if playhead >= duration {
            playhead = duration
            updatePosition(at: playhead)
            pause()
            return
        }

        updatePosition(at: playhead)
    }

    // MARK: - Интерполяция

    func updatePosition(at time: Double) {
        guard !keyframes.isEmpty else {
            return
        }

        let frames = keyframes.sorted {
            $0.time < $1.time
        }

        guard let first = frames.first,
              let last = frames.last else {
            return
        }

        if time <= first.time {
            pan = first.pan
            tilt = first.tilt
            return
        }

        if time >= last.time {
            pan = last.pan
            tilt = last.tilt
            return
        }

        for index in 0..<(frames.count - 1) {
            let start = frames[index]
            let end = frames[index + 1]

            if time >= start.time && time <= end.time {
                let segmentDuration = end.time - start.time

                guard segmentDuration > 0 else {
                    continue
                }

                let rawProgress = (time - start.time) / segmentDuration
                let progress = bezierProgress(rawProgress)

                pan = interpolate(
                    from: start.pan,
                    to: end.pan,
                    progress: progress
                )

                tilt = interpolate(
                    from: start.tilt,
                    to: end.tilt,
                    progress: progress
                )

                return
            }
        }
    }

    private func interpolate(
        from start: Double,
        to end: Double,
        progress: Double
    ) -> Double {
        start + (end - start) * progress
    }

    // MARK: - Кривая Безье

    private func bezierProgress(_ value: Double) -> Double {
        let t = max(0, min(1, value))

        let smooth = t * t * (3 - 2 * t)
        let strength = max(0, min(1, easing))

        return t * (1 - strength) + smooth * strength
    }

    // MARK: - Очистка

    deinit {
        playbackTimer?.invalidate()
    }
}
