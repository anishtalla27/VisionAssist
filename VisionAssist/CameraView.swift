//
//  CameraView.swift
//  VisionAssist
//
//  Created by Anish Talla on 12/29/25.
//

import SwiftUI
import AVFoundation

struct CameraView: UIViewRepresentable {

    private let manager = CameraManager()
    @State private var detections: [DetectedObject] = []

    func makeUIView(context: Context) -> UIView {
        let view = CameraPreviewView(session: manager.session)

        // Handle detection results
        manager.onDetections = { objects in
            context.coordinator.updateDetections(objects)
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // Coordinator to update bounding boxes
    class Coordinator {
        var parent: CameraView

        init(_ parent: CameraView) {
            self.parent = parent
        }

        func updateDetections(_ objects: [DetectedObject]) {
            NotificationCenter.default.post(name: .updateDetections, object: objects)
        }
    }
}

// UIView subclass to show preview + overlays
class CameraPreviewView: UIView {
    private var previewLayer: AVCaptureVideoPreviewLayer
    private var boxLayers: [CAShapeLayer] = []
    private var textLayers: [CATextLayer] = []
    private var lastDetections: [DetectedObject] = []
    private var persistence = 0

    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    init(session: AVCaptureSession) {
        self.previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        previewLayer.videoGravity = .resizeAspectFill
        (self.layer as! AVCaptureVideoPreviewLayer).session = session

        NotificationCenter.default.addObserver(self,
            selector: #selector(updateBoxes(_:)),
            name: .updateDetections, object: nil
        )
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateDetections(_ detections: [DetectedObject]) {
        DispatchQueue.main.async {
            if detections.isEmpty {
                if self.persistence > 0 {
                    self.persistence -= 1
                    self.drawBoxes(self.lastDetections)
                } else {
                    self.clearBoxes()
                }
                return
            }

            self.lastDetections = detections
            self.persistence = 6
            self.drawBoxes(detections)
        }
    }

    private func clearBoxes() {
        boxLayers.forEach { $0.removeFromSuperlayer() }
        textLayers.forEach { $0.removeFromSuperlayer() }
        boxLayers.removeAll()
        textLayers.removeAll()
    }

    private func drawBoxes(_ detections: [DetectedObject]) {
        clearBoxes()
        let W = bounds.width
        let H = bounds.height

        for det in detections {
            let r = det.rect
            let rect = CGRect(
                x: r.minX * W,
                y: (1 - r.maxY) * H,
                width: r.width * W,
                height: r.height * H
            )

            let box = CAShapeLayer()
            box.path = UIBezierPath(rect: rect).cgPath
            box.strokeColor = UIColor.yellow.cgColor
            box.lineWidth = 2
            box.fillColor = UIColor.clear.cgColor
            layer.addSublayer(box)
            boxLayers.append(box)

            let label = CATextLayer()
            label.string = "\(det.label) \(String(format: "%.2f", det.confidence))"
            label.fontSize = 13
            label.foregroundColor = UIColor.yellow.cgColor
            label.backgroundColor = UIColor.black.withAlphaComponent(0.5).cgColor
            label.frame = CGRect(x: rect.minX, y: rect.minY - 18, width: 140, height: 18)
            label.contentsScale = UIScreen.main.scale
            layer.addSublayer(label)
            textLayers.append(label)
        }
    }
    
    @objc func updateBoxes(_ note: Notification) {
        guard let detections = note.object as? [DetectedObject] else { return }
        print("UI received detections:", detections.count)
        updateDetections(detections)
    }
}

extension Notification.Name {
    static let updateDetections = Notification.Name("updateDetections")
}

