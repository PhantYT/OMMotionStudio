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

    // MARK: - Управление джойстиком

    @Published var joystickX: Double = 0
    @Published var joystickY: Double = 0

    @Published var sensitivity: Double = 1.0

    // MARK: - Положение виртуального стабилизатора

    @Published var pan: Double = 0
    @Published var tilt: Double = 0

    // MARK: - Timeline

    @Published var duration: Double = 10
    @Published var playhead: Double = 0

    @Published var isPlaying = false

    @Published var keyframes: [MotionKeyframe] = []

    // MARK: - Кривая Безье

    @Published var controlPoint1X: Double = 0.25
    @Published var controlPoint1Y: Double = 0.1

    @Published var controlPoint2X: Double = 0.75
    @Published var controlPoint2Y: Double = 0.9

    private var playbackTimer: Timer?
    private var lastPlaybackDate: Date?

    private let storageKey = "OMMotionStudio.Keyframes"

    init() {
        loadKeyframes()
    }

    // MARK: - Джойстик

    func moveJoystick(x: Double, y: Double) {
        joystickX = max(-1, min(1, x))
        joystickY = max(-1, min(1, y))

        pan += joystickX * sensitivity
        tilt += joystickY * sensitivity

        pan = max(-180, min(180, pan))
        tilt = max(-90, min(90, tilt))
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

    func deleteKeyframe(_ frame: MotionKeyframe) {
        keyframes.removeAll {
            $0.id == frame.id
        }

        saveKeyframes()
    }

    func clearKeyframes() {
        keyframes.removeAll()
        playhead = 0

        saveKeyframes()
    }

    func selectKeyframe(_ frame: MotionKeyframe) {
        playhead = frame.time
        pan = frame.pan
        tilt = frame.tilt
    }

    // MARK: - Сохранение проекта

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

    func setPlayhead(_ value: Double) {
        playhead = max(0, min(duration, value))
        updatePosition(at: playhead)
    }

    func setDuration(_ value: Double) {
        duration = max(1, min(300, value))
        playhead = min(playhead, duration)
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
            playhead = 0
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

        playhead = 0
        updatePosition(at: 0)
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

    // MARK: - Безье

    private func bezierProgress(_ value: Double) -> Double {

        let t = max(0, min(1, value))

        let x1 = controlPoint1X
        let y1 = controlPoint1Y

        let x2 = controlPoint2X
        let y2 = controlPoint2Y

        let inverse = 1 - t

        let result =
            3 * inverse * inverse * t * y1 +
            3 * inverse * t * t * y2 +
            t * t * t

        return max(0, min(1, result))
    }

    // MARK: - Очистка

    deinit {
        playbackTimer?.invalidate()
    }
}
