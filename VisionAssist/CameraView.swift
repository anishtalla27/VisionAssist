//
//  CameraView.swift
//  VisionAssist
//
//  Created by Anish Talla on 12/29/25.
//

import SwiftUI
import AVFoundation

struct CameraView: UIViewRepresentable {
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black
        
        context.coordinator.cameraManager.checkPermission { granted in
            if granted {
                DispatchQueue.main.async {
                    context.coordinator.setupCamera(in: view)
                }
            }
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Update preview layer frame when view size changes
        if let previewLayer = context.coordinator.cameraManager.previewLayer {
            DispatchQueue.main.async {
                previewLayer.frame = uiView.bounds
                
                // Ensure preview layer is added to view hierarchy if not already present
                if previewLayer.superlayer == nil {
                    uiView.layer.insertSublayer(previewLayer, at: 0)
                }
            }
        }
    }
    
    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.cameraManager.stopSession()
    }
    
    class Coordinator {
        let cameraManager = CameraManager()
        
        func setupCamera(in view: UIView) {
            cameraManager.setupSession()
            cameraManager.startSession()
            
            // Set initial frame for preview layer
            if let previewLayer = cameraManager.previewLayer {
                previewLayer.frame = view.bounds
                view.layer.insertSublayer(previewLayer, at: 0)
            }
        }
    }
}

// MARK: - Preview
#Preview {
    CameraView()
        .ignoresSafeArea()
}

