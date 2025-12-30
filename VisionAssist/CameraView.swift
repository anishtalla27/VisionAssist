//
//  CameraView.swift
//  VisionAssist
//
//  Fixed: Proper coordinate conversion, stable overlay rendering
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
        
        // Configure preview layer
        cameraManager.previewLayer.videoGravity = .resizeAspectFill
        cameraManager.previewLayer.frame = view.bounds
        view.layer.insertSublayer(cameraManager.previewLayer, at: 0)  // Ensure preview is at bottom
        
        // Configure overlay
        view.overlay.backgroundColor = .clear
        view.overlay.isUserInteractionEnabled = false
        view.overlay.frame = view.bounds
        view.addSubview(view.overlay)

        // Set up detection callback
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
        // Update frames when view bounds change
        previewLayer?.frame = bounds
        overlay.frame = bounds
    }
}

// UIView subclass for overlay drawing
class CameraPreviewView: UIView {
    private var detections: [DetectedObject] = []
    
    override func draw(_ rect: CGRect) {
        super.draw(rect)
        
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        
        // Clear any previous drawings
        ctx.clear(rect)

        for box in detections {
            let r = box.rect
            
            // CRITICAL FIX: Proper coordinate conversion
            // Vision framework uses bottom-left origin, UIKit uses top-left
            // Normalized coordinates: (0,0) = bottom-left, (1,1) = top-right
            let viewRect = CGRect(
                x: r.minX * bounds.width,
                y: (1 - r.maxY) * bounds.height,  // Flip Y-axis
                width: r.width * bounds.width,
                height: r.height * bounds.height
            )
            
            // Draw bounding box with thick yellow line
            ctx.setStrokeColor(UIColor.yellow.cgColor)
            ctx.setLineWidth(4)  // Increased thickness for visibility
            ctx.stroke(viewRect)

            // Draw label background
            let text = "\(box.label) \(Int(box.confidence * 100))%"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 16),
                .foregroundColor: UIColor.yellow
            ]
            
            let textSize = text.size(withAttributes: attrs)
            let labelOrigin = CGPoint(x: viewRect.minX, y: max(0, viewRect.minY - textSize.height - 4))
            
            // Draw semi-transparent background for text
            let backgroundRect = CGRect(
                x: labelOrigin.x,
                y: labelOrigin.y,
                width: textSize.width + 8,
                height: textSize.height + 4
            )
            ctx.setFillColor(UIColor.black.withAlphaComponent(0.7).cgColor)
            ctx.fill(backgroundRect)
            
            // Draw text
            text.draw(at: CGPoint(x: labelOrigin.x + 4, y: labelOrigin.y + 2), withAttributes: attrs)
        }
    }
    
    func updateDetections(_ detections: [DetectedObject]) {
        self.detections = detections
        // Force immediate redraw
        setNeedsDisplay()
    }
}
