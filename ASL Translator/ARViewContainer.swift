//
//  ARViewContainer.swift
//  ASL Translator
//
//  Created by Chufeng Huang on 4/7/25.
//

import Foundation
import SwiftUI
import ARKit

/// A SwiftUI wrapper around ARSCNView.
struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var viewModel: ARViewModel
    
    func makeUIView(context: Context) -> ARSCNView {
        // Create the ARSCNView with proper settings
        let arView = ARSCNView(frame: UIScreen.main.bounds)
        
        // Set background and other properties for full-screen appearance
        arView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        arView.contentMode = .scaleToFill
        
        // Configure scene settings for proper rendering
        arView.automaticallyUpdatesLighting = true
        
        // Set up the scene in our view model.
        viewModel.setupScene(in: arView)
        
        // Start the AR session.
        viewModel.startSession()
        
        return arView
    }
    
    func updateUIView(_ uiView: ARSCNView, context: Context) {
        // SwiftUI calls this when state changes.
        // Resize the view if needed
        uiView.frame = UIScreen.main.bounds
    }
}
