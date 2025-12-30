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
    private var boxLayers: [CALayer] = []
    private var lastDetections: [DetectedObject] = []
    private let persistenceFrames = 6 // show boxes for ~6 cycles if object disappears
    private var persistenceCounter = 0

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
        if detections.isEmpty {
            if persistenceCounter > 0 {
                persistenceCounter -= 1
                drawBoxes(lastDetections)
            } else {
                clearBoxes()
            }
            return
        }

        lastDetections = detections
        persistenceCounter = persistenceFrames
        drawBoxes(detections)
    }
    
    private func clearBoxes() {
        boxLayers.forEach { $0.removeFromSuperlayer() }
        boxLayers.removeAll()
    }
    
    private func drawBoxes(_ detections: [DetectedObject]) {
        clearBoxes()

        for det in detections {
            let n = det.rect

            let viewRect = CGRect(
                x: n.minX * bounds.width,
                y: (1 - n.maxY) * bounds.height,
                width: n.width * bounds.width,
                height: n.height * bounds.height
            )

            let box = CAShapeLayer()
            box.path = UIBezierPath(rect: viewRect).cgPath
            box.strokeColor = UIColor.yellow.cgColor
            box.lineWidth = 2
            box.fillColor = UIColor.clear.cgColor
            layer.addSublayer(box)
            boxLayers.append(box)

            // label text
            let textLayer = CATextLayer()
            textLayer.string = det.label + " " + String(format: "%.2f", det.confidence)
            textLayer.foregroundColor = UIColor.yellow.cgColor
            textLayer.fontSize = 14
            textLayer.frame = CGRect(x: viewRect.minX, y: viewRect.minY - 18, width: 120, height: 18)
            let screenScale = window?.windowScene?.screen.scale ?? UIScreen.main.scale
            textLayer.contentsScale = screenScale  // sharp text

            layer.addSublayer(textLayer)
            boxLayers.append(textLayer)
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

