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

    // Draw detection rectangles
    @objc func updateBoxes(_ note: Notification) {
        guard let objects = note.object as? [DetectedObject], let layer = self.layer as? AVCaptureVideoPreviewLayer else { return }

        // Remove old boxes
        boxLayers.forEach { $0.removeFromSuperlayer() }
        boxLayers.removeAll()

        for obj in objects {
            let convertedRect = layer.layerRectConverted(fromMetadataOutputRect: obj.rect)

            let shape = CAShapeLayer()
            shape.frame = convertedRect
            shape.path = UIBezierPath(rect: shape.bounds).cgPath
            shape.strokeColor = UIColor.yellow.cgColor
            shape.lineWidth = 2
            shape.fillColor = UIColor.clear.cgColor

            layer.addSublayer(shape)
            boxLayers.append(shape)
        }
    }
}

extension Notification.Name {
    static let updateDetections = Notification.Name("updateDetections")
}

