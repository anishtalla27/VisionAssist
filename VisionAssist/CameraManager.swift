import Foundation
import AVFoundation
import Vision
import UIKit

class CameraManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    let session = AVCaptureSession()
    private let detector = ObjectDetector()
    private var lastProcessTime = Date()

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

        // Only process 1 frame every 0.2 seconds to avoid overload
        let now = Date()
        guard now.timeIntervalSince(lastProcessTime) > 0.2 else { return }
        lastProcessTime = now

        DispatchQueue.global(qos: .userInitiated).async {
            let detections = self.detector.detect(pixelBuffer: pixelBuffer)

            DispatchQueue.main.async {
                self.onDetections?(detections)
            }
        }
    }
}
