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
    private var displayLink: CADisplayLink?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupDisplayLink()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupDisplayLink()
    }
    
    private func setupDisplayLink() {
        displayLink = CADisplayLink(target: self, selector: #selector(refresh))
        displayLink?.add(to: .main, forMode: .common)
    }
    
    @objc private func refresh() {
        overlay.setNeedsDisplay()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
        overlay.frame = bounds
    }
    
    deinit {
        displayLink?.invalidate()
    }
}

// UIView subclass for overlay drawing with temporal smoothing
class CameraPreviewView: UIView {
    private var trackedDetections: [TrackedDetection] = []
    weak var previewLayer: AVCaptureVideoPreviewLayer?
    
    // Stabilization parameters
    private let minConfirmationFrames = 2      // Must be detected in N frames to show
    private let maxDetectionAge: TimeInterval = 0.5  // Keep for 0.5s after last seen
    
    override func draw(_ rect: CGRect) {
        super.draw(rect)
        
        guard let ctx = UIGraphicsGetCurrentContext(),
              let previewLayer = previewLayer else { return }
        
        ctx.clear(rect)
        
        // Remove stale detections
        trackedDetections.removeAll { $0.isStale(maxAge: maxDetectionAge) }
        
        // Draw only confirmed detections
        for tracked in trackedDetections where tracked.isConfirmed(minFrames: minConfirmationFrames) {
            // Use smoothed rect for stable display
            let convertedRect = previewLayer.layerRectConverted(fromMetadataOutputRect: tracked.smoothedRect)
            
            // Clamp to screen bounds
            let clampedRect = convertedRect.intersection(bounds)
            
            guard !clampedRect.isNull, clampedRect.width > 10, clampedRect.height > 10 else {
                continue
            }
            
            // Calculate alpha based on age (fade out effect)
            let age = Date().timeIntervalSince(tracked.lastSeen)
            let fadeStartTime: TimeInterval = 0.3
            let alpha: CGFloat = age > fadeStartTime ? max(0, 1 - CGFloat((age - fadeStartTime) / (maxDetectionAge - fadeStartTime))) : 1.0
            
            // Draw bounding box with fade
            ctx.setStrokeColor(UIColor.yellow.withAlphaComponent(alpha).cgColor)
            ctx.setLineWidth(4)
            ctx.stroke(clampedRect)
            
            // Draw label
            let text = "\(tracked.label) \(Int(tracked.confidence * 100))%"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 16),
                .foregroundColor: UIColor.yellow.withAlphaComponent(alpha)
            ]
            
            let textSize = text.size(withAttributes: attrs)
            
            // Smart label positioning
            var labelOrigin: CGPoint
            if clampedRect.minY > textSize.height + 8 {
                labelOrigin = CGPoint(x: clampedRect.minX, y: clampedRect.minY - textSize.height - 4)
            } else {
                labelOrigin = CGPoint(x: clampedRect.minX + 4, y: clampedRect.minY + 4)
            }
            
            // Keep label on screen
            if labelOrigin.x + textSize.width + 8 > bounds.width {
                labelOrigin.x = bounds.width - textSize.width - 12
            }
            labelOrigin.x = max(4, labelOrigin.x)
            
            // Draw text background
            let backgroundRect = CGRect(
                x: labelOrigin.x,
                y: labelOrigin.y,
                width: textSize.width + 8,
                height: textSize.height + 4
            )
            ctx.setFillColor(UIColor.black.withAlphaComponent(0.7 * alpha).cgColor)
            ctx.fill(backgroundRect)
            
            // Draw text
            text.draw(at: CGPoint(x: labelOrigin.x + 4, y: labelOrigin.y + 2), withAttributes: attrs)
        }
    }
    
    func updateDetections(_ detections: [DetectedObject]) {
        // Match new detections with existing tracked detections
        var matchedIndices = Set<Int>()
        
        // Update existing tracked detections
        for tracked in trackedDetections {
            if let index = detections.firstIndex(where: { tracked.matches($0) }) {
                tracked.update(with: detections[index])
                matchedIndices.insert(index)
            }
        }
        
        // Add new detections that weren't matched
        for (index, detection) in detections.enumerated() {
            if !matchedIndices.contains(index) {
                trackedDetections.append(TrackedDetection(detection: detection))
            }
        }
        
        // Trigger redraw
        setNeedsDisplay()
    }
}
