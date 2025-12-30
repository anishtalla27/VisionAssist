//
//  TrackedDetection.swift
//  VisionAssist
//
//  Temporal smoothing for stable object detection
//

import Foundation
import CoreGraphics

class TrackedDetection {
    let id: UUID
    var label: String
    var confidence: Float
    var rect: CGRect
    var lastSeen: Date
    var firstSeen: Date
    var consecutiveFrames: Int
    var smoothedRect: CGRect
    
    // Smoothing parameters
    private let smoothingFactor: CGFloat = 0.3  // Lower = smoother but more lag
    
    init(detection: DetectedObject) {
        self.id = UUID()
        self.label = detection.label
        self.confidence = detection.confidence
        self.rect = detection.rect
        self.smoothedRect = detection.rect
        self.lastSeen = Date()
        self.firstSeen = Date()
        self.consecutiveFrames = 1
    }
    
    func update(with detection: DetectedObject) {
        self.label = detection.label
        self.confidence = detection.confidence
        self.lastSeen = Date()
        self.consecutiveFrames += 1
        
        // Smooth the rectangle position using exponential moving average
        let newRect = detection.rect
        self.smoothedRect = CGRect(
            x: smoothedRect.origin.x * (1 - smoothingFactor) + newRect.origin.x * smoothingFactor,
            y: smoothedRect.origin.y * (1 - smoothingFactor) + newRect.origin.y * smoothingFactor,
            width: smoothedRect.width * (1 - smoothingFactor) + newRect.width * smoothingFactor,
            height: smoothedRect.height * (1 - smoothingFactor) + newRect.height * smoothingFactor
        )
        
        self.rect = newRect
    }
    
    func isStale(maxAge: TimeInterval = 0.5) -> Bool {
        return Date().timeIntervalSince(lastSeen) > maxAge
    }
    
    func isConfirmed(minFrames: Int = 2) -> Bool {
        return consecutiveFrames >= minFrames
    }
    
    func matches(_ detection: DetectedObject, iouThreshold: Float = 0.4) -> Bool {
        // Same label and overlapping boxes
        guard detection.label == label else { return false }
        
        let iou = calculateIOU(rect1: rect, rect2: detection.rect)
        return iou > iouThreshold
    }
    
    private func calculateIOU(rect1: CGRect, rect2: CGRect) -> Float {
        let intersection = rect1.intersection(rect2)
        if intersection.isNull { return 0 }
        
        let intersectionArea = intersection.width * intersection.height
        let unionArea = rect1.width * rect1.height + rect2.width * rect2.height - intersectionArea
        
        return Float(intersectionArea / unionArea)
    }
}

