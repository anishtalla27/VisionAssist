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
        view.overlay.previewLayer = cameraManager.previewLayer  // Pass preview layer for coordinate conversion
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
    weak var previewLayer: AVCaptureVideoPreviewLayer?  // Reference for coordinate conversion
    
    override func draw(_ rect: CGRect) {
        super.draw(rect)
        
        guard let ctx = UIGraphicsGetCurrentContext(),
              let previewLayer = previewLayer else { return }
        
        // Clear any previous drawings
        ctx.clear(rect)

        for box in detections {
            // Convert Vision coordinates to layer coordinates
            let convertedRect = previewLayer.layerRectConverted(fromMetadataOutputRect: box.rect)
            
            // CRITICAL FIX: Clamp bounding box to screen bounds
            let clampedRect = convertedRect.intersection(bounds)
            
            // Skip if box is completely off-screen or too small
            guard !clampedRect.isNull, clampedRect.width > 10, clampedRect.height > 10 else {
                continue
            }
            
            // Draw bounding box
            ctx.setStrokeColor(UIColor.yellow.cgColor)
            ctx.setLineWidth(4)
            ctx.stroke(clampedRect)

            // Draw label with smart positioning
            let text = "\(box.label) \(Int(box.confidence * 100))%"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 16),
                .foregroundColor: UIColor.yellow
            ]
            
            let textSize = text.size(withAttributes: attrs)
            
            // CRITICAL FIX: Smart label positioning
            // Try above box first, if not enough space, put inside box at top
            var labelOrigin: CGPoint
            
            if clampedRect.minY > textSize.height + 8 {
                // Enough space above box
                labelOrigin = CGPoint(x: clampedRect.minX, y: clampedRect.minY - textSize.height - 4)
            } else {
                // Not enough space above, put inside box at top
                labelOrigin = CGPoint(x: clampedRect.minX + 4, y: clampedRect.minY + 4)
            }
            
            // Ensure label doesn't go off right edge
            if labelOrigin.x + textSize.width + 8 > bounds.width {
                labelOrigin.x = bounds.width - textSize.width - 12
            }
            
            // Ensure label doesn't go off left edge
            labelOrigin.x = max(4, labelOrigin.x)
            
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
