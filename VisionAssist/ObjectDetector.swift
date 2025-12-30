//
//  ObjectDetector.swift
//  VisionAssist
//
//  Fixed: Model loads once, proper coordinate handling, optimized performance
//

import CoreML
import Vision
import CoreVideo
import Foundation

struct DetectedObject {
    let label: String
    let confidence: Float
    let rect: CGRect  // Normalized coordinates [0, 1]
}

class ObjectDetector {
    // CRITICAL FIX: Load model ONCE and reuse it
    private var vnModel: VNCoreMLModel?
    private let modelInputSize: CGFloat = 640.0  // YOLO11n input size
    
    init() {
        // Load model on initialization
        self.vnModel = loadModel()
    }
    
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

        guard let url = bundle.url(forResource: "yolo11m", withExtension: "mlmodelc") else {
            print("❌ yolo11m.mlmodelc not found in bundle")
            return nil
        }

        print("✅ Loading model ONCE from:", url)

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
        // Use the pre-loaded model instead of reloading
        guard let vnModel = self.vnModel else {
            print("❌ Model not loaded")
            return []
        }
        
        var detectedObjects: [DetectedObject] = []
        let semaphore = DispatchSemaphore(value: 0)
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        
        let request = VNCoreMLRequest(model: vnModel) { [weak self] request, error in
            if let error = error {
                print("❌ Error in detection: \(error)")
                semaphore.signal()
                return
            }
            
            guard let self = self else {
                semaphore.signal()
                return
            }
            
            // Safely unwrap request.results
            guard let results = request.results else {
                semaphore.signal()
                return
            }
            
            // Try to get VNRecognizedObjectObservation first (if model outputs that format)
            if let recognizedObservations = results as? [VNRecognizedObjectObservation] {
                for observation in recognizedObservations {
                    guard let topLabelObservation = observation.labels.first else { continue }
                    
                    // Use normalized bounding box directly
                    let rect = observation.boundingBox
                    
                    let detectedObject = DetectedObject(
                        label: topLabelObservation.identifier,
                        confidence: topLabelObservation.confidence,
                        rect: rect
                    )
                    detectedObjects.append(detectedObject)
                }
            } else {
                // Handle raw outputs (YOLO models typically output MLMultiArray)
                detectedObjects = self.parseYOLOOutputs(observations: results)
            }
            
            semaphore.signal()
        }
        
        request.imageCropAndScaleOption = .scaleFill
        
        do {
            try handler.perform([request])
            semaphore.wait()
        } catch {
            print("❌ Error performing request: \(error)")
            return []
        }
        
        if !detectedObjects.isEmpty {
            print("✅ Detections this frame: \(detectedObjects.count)")
        }
        return detectedObjects
    }
    
    private func parseYOLOOutputs(observations: [VNObservation]) -> [DetectedObject] {
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

        guard let featureObs = observations.first as? VNCoreMLFeatureValueObservation,
              let multiArray = featureObs.featureValue.multiArrayValue else {
            return []
        }

        let shape = multiArray.shape

        // Expect [1, 84, 8400]
        guard shape.count == 3,
              shape[0].intValue == 1,
              shape[1].intValue == 84 else {
            print("❌ Unexpected YOLO output shape: \(shape)")
            return []
        }

        let channels = shape[1].intValue      // 84
        let numDetections = shape[2].intValue // 8400

        let coordsCount = 4
        let numClasses = channels - coordsCount

        let confThreshold: Float = 0.25

        for det in 0..<numDetections {
            // Read bbox center x, center y, width, height from channel 0..3
            // CRITICAL: YOLO outputs in PIXEL space [0-640], not normalized!
            let xCenter = multiArray[[0, 0, NSNumber(value: det)]].doubleValue
            let yCenter = multiArray[[0, 1, NSNumber(value: det)]].doubleValue
            let boxWidth = multiArray[[0, 2, NSNumber(value: det)]].doubleValue
            let boxHeight = multiArray[[0, 3, NSNumber(value: det)]].doubleValue

            var bestScore: Float = 0
            var bestClassIndex = 0

            // Class scores start at channel index 4
            for c in 0..<numClasses {
                let score = multiArray[[0, NSNumber(value: 4 + c), NSNumber(value: det)]].floatValue
                if score > bestScore {
                    bestScore = score
                    bestClassIndex = c
                }
            }

            if bestScore < confThreshold {
                continue
            }

            // CRITICAL FIX: Normalize coordinates from pixel space to [0, 1]
            let normalizedX = (xCenter - boxWidth / 2) / Double(modelInputSize)
            let normalizedY = (yCenter - boxHeight / 2) / Double(modelInputSize)
            let normalizedWidth = boxWidth / Double(modelInputSize)
            let normalizedHeight = boxHeight / Double(modelInputSize)
            
            // Clamp to valid range [0, 1]
            let rect = CGRect(
                x: max(0, min(1, CGFloat(normalizedX))),
                y: max(0, min(1, CGFloat(normalizedY))),
                width: max(0, min(1, CGFloat(normalizedWidth))),
                height: max(0, min(1, CGFloat(normalizedHeight)))
            )

            let label = bestClassIndex < classNames.count ? classNames[bestClassIndex] : "class_\(bestClassIndex)"

            detectedObjects.append(
                DetectedObject(
                    label: label,
                    confidence: bestScore,
                    rect: rect
                )
            )
        }

        return detectedObjects
    }
}
