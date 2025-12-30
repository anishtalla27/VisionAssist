import Foundation
import AVFoundation
import Vision
import UIKit

class CameraManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    let session = AVCaptureSession()
    private let detector = ObjectDetector()
    private var frameCount = 0

    // Callback that sends detections back to UI
    var onDetections: (([DetectedObject]) -> Void)?

    override init() {
        super.init()
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

        // Detect every 3rd frame for smooth preview
        frameCount += 1
        if frameCount % 3 != 0 { return }

        DispatchQueue.global(qos: .userInitiated).async {
            let detections = self.detector.detect(pixelBuffer: pixelBuffer)

            DispatchQueue.main.async {
                self.onDetections?(detections)
                NotificationCenter.default.post(name: .updateDetections, object: detections)
            }
        }
    }
}
