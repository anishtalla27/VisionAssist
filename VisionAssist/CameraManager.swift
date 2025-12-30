import Foundation
import AVFoundation
import Vision
import UIKit
import Combine

class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    let session = AVCaptureSession()
    private let detector = ObjectDetector()
    let previewLayer = AVCaptureVideoPreviewLayer()
    let voiceManager = VoiceManager()

    // Callback that sends detections back to UI
    var onDetections: (([DetectedObject]) -> Void)?

    override init() {
        super.init()
        previewLayer.session = session
        configureSession()
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .high

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            print("Camera input unavailable")
            session.commitConfiguration()
            return
        }

        if session.canAddInput(input) { session.addInput(input) }

        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera.queue"))
        if session.canAddOutput(output) { session.addOutput(output) }

        session.commitConfiguration()
        session.startRunning()
    }

    // Called every frame from camera
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Run detection
        let detections = detector.detect(pixelBuffer: pixelBuffer)

        // Send results to UI
        DispatchQueue.main.async { [weak self] in
            self?.onDetections?(detections)
            
            // Announce detections via voice
            self?.voiceManager.announceDetections(detections)
        }
    }
}
