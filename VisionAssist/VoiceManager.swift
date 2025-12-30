//
//  VoiceManager.swift
//  VisionAssist
//
//  Manages text-to-speech announcements for detected objects
//

import AVFoundation
import Foundation

class VoiceManager: NSObject, ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()
    
    // Settings
    @Published var isEnabled: Bool = true
    @Published var speechRate: Float = 0.5  // 0.0 (slow) to 1.0 (fast)
    
    // Debouncing - prevent announcement spam
    private var lastAnnouncedObjects: Set<String> = []
    private var lastAnnouncementTime: Date = .distantPast
    private let minimumAnnouncementInterval: TimeInterval = 2.0  // 2 seconds between announcements
    
    override init() {
        super.init()
        synthesizer.delegate = self
    }
    
    func announceDetections(_ detections: [DetectedObject]) {
        guard isEnabled else { return }
        guard !synthesizer.isSpeaking else { return }  // Don't interrupt current speech
        
        // Check if enough time has passed since last announcement
        let now = Date()
        guard now.timeIntervalSince(lastAnnouncementTime) >= minimumAnnouncementInterval else {
            return
        }
        
        // Get high-confidence detections (60%+)
        let highConfidenceDetections = detections.filter { $0.confidence >= 0.60 }
        
        guard !highConfidenceDetections.isEmpty else { return }
        
        // Find new objects that weren't in the last announcement
        let currentObjects = Set(highConfidenceDetections.map { $0.label })
        let newObjects = currentObjects.subtracting(lastAnnouncedObjects)
        
        // If no new objects, don't announce
        guard !newObjects.isEmpty else { return }
        
        // Create announcement
        let announcement = createAnnouncement(for: Array(newObjects), from: highConfidenceDetections)
        
        // Speak it
        speak(announcement)
        
        // Update tracking
        lastAnnouncedObjects = currentObjects
        lastAnnouncementTime = now
    }
    
    private func createAnnouncement(for objects: [String], from detections: [DetectedObject]) -> String {
        // Sort by confidence (highest first)
        let sortedDetections = detections
            .filter { objects.contains($0.label) }
            .sorted { $0.confidence > $1.confidence }
        
        if sortedDetections.count == 1 {
            let detection = sortedDetections[0]
            return "I see a \(detection.label)"
        } else if sortedDetections.count == 2 {
            return "I see a \(sortedDetections[0].label) and a \(sortedDetections[1].label)"
        } else {
            // Multiple objects
            let firstTwo = sortedDetections.prefix(2).map { $0.label }
            let remaining = sortedDetections.count - 2
            return "I see a \(firstTwo[0]), a \(firstTwo[1]), and \(remaining) more object\(remaining == 1 ? "" : "s")"
        }
    }
    
    func speak(_ text: String) {
        guard isEnabled else { return }
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = speechRate
        utterance.volume = 1.0
        
        synthesizer.speak(utterance)
    }
    
    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
    }
    
    func clearHistory() {
        lastAnnouncedObjects.removeAll()
        lastAnnouncementTime = .distantPast
    }
}

// MARK: - AVSpeechSynthesizerDelegate
extension VoiceManager: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // Speech finished, ready for next announcement
    }
}

