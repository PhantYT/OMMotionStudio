
import Foundation
import AVFoundation
import Photos
import SwiftUI
import UIKit

@MainActor
final class CameraManager: NSObject, ObservableObject {

    @Published var isRecording = false
    @Published var isReady = false
    @Published var status = "Камера не запущена"

    let session = AVCaptureSession()

    private let movieOutput = AVCaptureMovieFileOutput()
    private var configured = false

    func start() {
        guard !configured else {
            if !session.isRunning {
                DispatchQueue.global(qos: .userInitiated).async {
                    self.session.startRunning()
                }
            }
            return
        }

        Task {
            await configure()
        }
    }

    private func configure() async {
        let cameraGranted = await AVCaptureDevice.requestAccess(for: .video)
        let audioGranted = await AVCaptureDevice.requestAccess(for: .audio)

        guard cameraGranted else {
            status = "Нет разрешения на камеру"
            return
        }

        session.beginConfiguration()
        session.sessionPreset = .high

        guard let camera = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) else {
            session.commitConfiguration()
            status = "Камера не найдена"
            return
        }

        do {
            let videoInput = try AVCaptureDeviceInput(device: camera)

            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
            }

            if audioGranted,
               let microphone = AVCaptureDevice.default(for: .audio) {
                let audioInput = try AVCaptureDeviceInput(device: microphone)

                if session.canAddInput(audioInput) {
                    session.addInput(audioInput)
                }
            }

            if session.canAddOutput(movieOutput) {
                session.addOutput(movieOutput)
            }

            session.commitConfiguration()
            configured = true
            isReady = true
            status = "Камера готова"

            DispatchQueue.global(qos: .userInitiated).async {
                self.session.startRunning()
            }

        } catch {
            session.commitConfiguration()
            status = "Ошибка камеры: \(error.localizedDescription)"
        }
    }

    func stopSession() {
        if session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                self.session.stopRunning()
            }
        }
    }

    func record() {
        guard configured, session.isRunning else {
            status = "Сначала запусти камеру"
            return
        }

        guard !movieOutput.isRecording else { return }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        movieOutput.startRecording(to: url, recordingDelegate: self)
        isRecording = true
        status = "Идёт запись"
    }

    func stopRecording() {
        guard movieOutput.isRecording else { return }
        movieOutput.stopRecording()
    }
}

extension CameraManager: AVCaptureFileOutputRecordingDelegate {

    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor in
            self.isRecording = false

            if let error {
                self.status = "Ошибка записи: \(error.localizedDescription)"
                return
            }

            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                guard status == .authorized || status == .limited else {
                    Task { @MainActor in
                        self.status = "Нет разрешения на сохранение видео"
                    }
                    return
                }

                PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(
                        atFileURL: outputFileURL
                    )
                } completionHandler: { success, error in
                    try? FileManager.default.removeItem(at: outputFileURL)

                    Task { @MainActor in
                        if success {
                            self.status = "Видео сохранено в Фото"
                        } else {
                            self.status = "Ошибка сохранения: \(error?.localizedDescription ?? "неизвестно")"
                        }
                    }
                }
            }
        }
    }
}

struct CameraPreview: UIViewRepresentable {

    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
    }
}

final class PreviewView: UIView {

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}
