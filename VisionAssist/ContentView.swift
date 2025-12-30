//
//  ContentView.swift
//  VisionAssist
//
//  Created by Anish Talla on 12/29/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    
    var body: some View {
        ZStack {
            CameraView(cameraManager: cameraManager)
                .ignoresSafeArea()
            
            // Voice toggle button
            VStack {
                HStack {
                    Spacer()
                    
                    Button(action: {
                        cameraManager.voiceManager.isEnabled.toggle()
                    }) {
                        Image(systemName: cameraManager.voiceManager.isEnabled ? "speaker.wave.3.fill" : "speaker.slash.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .padding()
                }
                
                Spacer()
            }
        }
    }
}

#Preview {
    ContentView()
}
