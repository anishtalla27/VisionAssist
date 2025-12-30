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
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)

        cameraManager.previewLayer.frame = view.bounds
        cameraManager.previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(cameraManager.previewLayer)

        let overlay = CameraPreviewView()
        overlay.frame = view.bounds
        overlay.isUserInteractionEnabled = false
        overlay.backgroundColor = .clear
        view.addSubview(overlay)

        cameraManager.onDetections = { detections in
            DispatchQueue.main.async {
                overlay.updateDetections(detections)
            }
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let previewLayer = cameraManager.previewLayer.superlayer {
            cameraManager.previewLayer.frame = uiView.bounds
        }
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

