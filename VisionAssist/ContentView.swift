//
//  ContentView.swift
//  VisionAssist
//
//  Created by Anish Talla on 12/29/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        CameraView()        // will show live camera when we add those files
            .ignoresSafeArea()
    }
}

#Preview {
    ContentView()
}
