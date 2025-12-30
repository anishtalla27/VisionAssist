//
//  CameraView.swift
//  VisionAssist
//
//  Created by Anish Talla on 12/29/25.
//

import SwiftUI
import AVFoundation

struct CameraView: UIViewRepresentable {
    @ObservedObject var cameraManager = CameraManager()
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeUIView(context: Context) -> UIView {
        let view = CameraContainerView()
        context.coordinator.containerView = view
        context.coordinator.overlay = view.overlay
        context.coordinator.cameraManager = cameraManager
        view.previewLayer = cameraManager.previewLayer
        
        cameraManager.previewLayer.videoGravity = .resizeAspectFill
        cameraManager.previewLayer.frame = view.bounds
        view.layer.addSublayer(cameraManager.previewLayer)
        view.overlay.backgroundColor = .clear
        view.overlay.isUserInteractionEnabled = false
        view.addSubview(view.overlay)

        cameraManager.onDetections = { detections in
            DispatchQueue.main.async {
                view.overlay.updateDetections(detections)
            }
        }
        
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let containerView = uiView as? CameraContainerView else { return }
        cameraManager.previewLayer.frame = containerView.bounds
        containerView.overlay.frame = containerView.bounds
    }
    
    class Coordinator {
        weak var containerView: CameraContainerView?
        weak var overlay: CameraPreviewView?
        weak var cameraManager: CameraManager?
    }
}

class CameraContainerView: UIView {
    let overlay = CameraPreviewView()
    weak var previewLayer: AVCaptureVideoPreviewLayer?
    
    override func layoutSubviews() {
        super.layoutSubviews()
        // Update preview layer frame when view bounds change
        previewLayer?.frame = bounds
        overlay.frame = bounds
    }
}

// UIView subclass for overlay drawing
class CameraPreviewView: UIView {
    private var detections: [DetectedObject] = []
    
    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        for box in detections {
            let r = box.rect
            let viewRect = CGRect(
                x: r.minX * bounds.width,
                y: (1 - r.maxY) * bounds.height,
                width: r.width * bounds.width,
                height: r.height * bounds.height
            )
            
            ctx.setStrokeColor(UIColor.yellow.cgColor)
            ctx.setLineWidth(3)
            ctx.stroke(viewRect)

            let text = "\(box.label) \(Int(box.confidence * 100))%"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 14),
                .foregroundColor: UIColor.yellow
            ]
            text.draw(at: CGPoint(x: viewRect.minX, y: viewRect.minY - 18), withAttributes: attrs)
        }
    }
    
    func updateDetections(_ detections: [DetectedObject]) {
        self.detections = detections
        setNeedsDisplay()
    }
}

