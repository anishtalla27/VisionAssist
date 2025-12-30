//
//  ObjectDetector.swift
//  VisionAssist
//
//  Created by Anish Talla on 12/29/25.
//

import CoreML
import Vision
import CoreVideo
import Foundation

struct DetectedObject {
    let label: String
    let confidence: Float
    let rect: CGRect
}

class ObjectDetector {
    // Load YOLO .mlpackage model from bundle
    private func loadModel() -> VNCoreMLModel? {
        let bundle = Bundle.main

        // Debug: list all compiled CoreML models in the bundle
        if let urls = bundle.urls(forResourcesWithExtension: "mlmodelc", subdirectory: nil) {
            print("📦 Found mlmodelc files in bundle:")
            for u in urls {
                print("   -", u.lastPathComponent)
            }
        }

        guard let url = bundle.url(forResource: "yolo11n", withExtension: "mlmodelc") else {
            print("❌ yolo11n.mlmodelc not found in bundle")
            return nil
        }

        print("✅ Loading model from:", url)

        do {
            let model = try MLModel(contentsOf: url)
            let vnModel = try VNCoreMLModel(for: model)
            return vnModel
        } catch {
            print("❌ Model load failed:", error)
            return nil
        }
    }

    
    func detect(pixelBuffer: CVPixelBuffer) -> [DetectedObject] {
        guard let vnModel = loadModel() else { return [] }
        
        var detectedObjects: [DetectedObject] = []
        let semaphore = DispatchSemaphore(value: 0)
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        
        let request = VNCoreMLRequest(model: vnModel) { [weak self] request, error in
            if let error = error {
                print("Error in detection: \(error)")
                semaphore.signal()
                return
            }
            
            guard let self = self else {
                semaphore.signal()
                return
            }
            
            print("🔎 Inference result:", type(of: request.results))
            print("Result count:", request.results?.count ?? 0)
            
            // Safely unwrap request.results
            guard let results = request.results else {
                semaphore.signal()
                return
            }
            
            // Try to get VNRecognizedObjectObservation first (if model outputs that format)
            if let recognizedObservations = results as? [VNRecognizedObjectObservation] {
                for observation in recognizedObservations {
                    guard let topLabelObservation = observation.labels.first else { continue }
                    
                    // Convert bounding box from normalized coordinates (0-1) to pixel coordinates
                    let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
                    let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
                    
                    let rect = CGRect(
                        x: observation.boundingBox.origin.x * width,
                        y: (1 - observation.boundingBox.origin.y - observation.boundingBox.height) * height,
                        width: observation.boundingBox.width * width,
                        height: observation.boundingBox.height * height
                    )
                    
                    let detectedObject = DetectedObject(
                        label: topLabelObservation.identifier,
                        confidence: topLabelObservation.confidence,
                        rect: rect
                    )
                    detectedObjects.append(detectedObject)
                }
            } else {
                // Handle raw outputs (YOLO models typically output MLMultiArray)
                detectedObjects = self.parseYOLOOutputs(observations: results, pixelBuffer: pixelBuffer)
            }
            
            semaphore.signal()
        }
        
        request.imageCropAndScaleOption = .scaleFill
        
        do {
            try handler.perform([request])
            semaphore.wait()
        } catch {
            print("Error performing request: \(error)")
            return []
        }
        
        return detectedObjects
    }
    
    private func parseYOLOOutputs(observations: [VNObservation], pixelBuffer: CVPixelBuffer) -> [DetectedObject] {
        var detectedObjects: [DetectedObject] = []
        
        // COCO class names for YOLO11n
        let classNames = [
            "person", "bicycle", "car", "motorcycle", "airplane", "bus", "train", "truck", "boat",
            "traffic light", "fire hydrant", "stop sign", "parking meter", "bench", "bird", "cat", "dog",
            "horse", "sheep", "cow", "elephant", "bear", "zebra", "giraffe", "backpack", "umbrella",
            "handbag", "tie", "suitcase", "frisbee", "skis", "snowboard", "sports ball", "kite",
            "baseball bat", "baseball glove", "skateboard", "surfboard", "tennis racket", "bottle",
            "wine glass", "cup", "fork", "knife", "spoon", "bowl", "banana", "apple", "sandwich",
            "orange", "broccoli", "carrot", "hot dog", "pizza", "donut", "cake", "chair", "couch",
            "potted plant", "bed", "dining table", "toilet", "tv", "laptop", "mouse", "remote",
            "keyboard", "cell phone", "microwave", "oven", "toaster", "sink", "refrigerator", "book",
            "clock", "vase", "scissors", "teddy bear", "hair drier", "toothbrush"
        ]
        
        let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        
        for observation in observations {
            if let coreMLObservation = observation as? VNCoreMLFeatureValueObservation,
               let multiArray = coreMLObservation.featureValue.multiArrayValue {
                
                // YOLO output format is typically [1, num_detections, 84] where 84 = 4 (bbox) + 80 (classes)
                // Or it could be flattened: [num_detections * 84]
                let shape = multiArray.shape
                
                if shape.count >= 2 {
                    let numDetections = shape[1].intValue
                    let featuresPerDetection = shape.count > 2 ? shape[2].intValue : (multiArray.count / numDetections)
                    
                    for i in 0..<numDetections {
                        let baseIndex = i * featuresPerDetection
                        
                        guard baseIndex + 4 < multiArray.count else { continue }
                        
                        // Get bounding box coordinates (normalized)
                        let xCenter = multiArray[baseIndex].doubleValue
                        let yCenter = multiArray[baseIndex + 1].doubleValue
                        let boxWidth = multiArray[baseIndex + 2].doubleValue
                        let boxHeight = multiArray[baseIndex + 3].doubleValue
                        
                        // Find class with highest confidence
                        var maxClassScore: Float = 0
                        var maxClassIndex = 0
                        
                        for j in 4..<min(featuresPerDetection, 84) {
                            let classIndex = baseIndex + j
                            guard classIndex < multiArray.count else { break }
                            let score = multiArray[classIndex].floatValue
                            if score > maxClassScore {
                                maxClassScore = score
                                maxClassIndex = j - 4
                            }
                        }
                        
                        // Confidence threshold
                        guard maxClassScore > 0.25 else { continue }
                        
                        // Convert normalized coordinates to pixel coordinates
                        // YOLO uses center format, convert to origin + size
                        let rect = CGRect(
                            x: CGFloat(xCenter - boxWidth / 2) * width,
                            y: CGFloat(1 - yCenter - boxHeight / 2) * height,
                            width: CGFloat(boxWidth) * width,
                            height: CGFloat(boxHeight) * height
                        )
                        
                        let label = maxClassIndex < classNames.count ? classNames[maxClassIndex] : "class_\(maxClassIndex)"
                        
                        detectedObjects.append(DetectedObject(
                            label: label,
                            confidence: maxClassScore,
                            rect: rect
                        ))
                    }
                }
            }
        }
        
        return detectedObjects
    }
}

