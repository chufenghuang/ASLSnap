//
//  ContentView.swift
//  ASL Translator
//
//  Created by Chufeng Huang on 4/7/25.
//

import Foundation
import SwiftUI
import ARKit

struct ContentView: View {
    // Create the ARViewModel as a @StateObject
    @StateObject var viewModel = ARViewModel()
    
    // State to track if AR view is active
    @State private var showARView = false
    
    var body: some View {
        if showARView {
            // Show AR View when active
            ZStack {
                ARViewContainer(viewModel: viewModel)
                    .edgesIgnoringSafeArea(.all)
                
                // Status and controls overlay
                VStack {
                    // Back button
                    HStack {
                        Button(action: {
                            showARView = false
                        }) {
                            Image(systemName: "arrow.left.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.white)
                                .padding(20)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                        .padding(.leading, 20)
                        .padding(.top, 20)
                        
                        Spacer()
                    }
                    
                    Spacer()
                    
                    // Hand detection status at the bottom
                    HStack {
                        Spacer()
                        Text(viewModel.isHandDetected ? "Hand Detected" : "No Hand")
                            .padding(8)
                            .background(viewModel.isHandDetected ? Color.green.opacity(0.7) : Color.red.opacity(0.7))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                            .padding(.trailing, 20)
                            .padding(.bottom, 30)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .ignoresSafeArea()
            .onAppear {
                // Prevent screen from sleeping while camera is active
                UIApplication.shared.isIdleTimerDisabled = true
            }
            .onDisappear {
                // Allow screen to sleep again when camera is inactive
                UIApplication.shared.isIdleTimerDisabled = false
            }
        } else {
            // Home page with improved layout
            GeometryReader { geometry in
                ZStack {
                    Color.black
                    
                    VStack {
                        // Header area with scaled sizing
                        VStack(spacing: 10) {
                            Image(systemName: "hand.raised.fill")
                                .font(.system(size: geometry.size.width * 0.15))
                                .foregroundColor(.green)
                                .padding(.top, geometry.size.height * 0.1)
                                
                            Text("ASL Translator")
                                .font(.system(size: min(geometry.size.width * 0.1, 36), weight: .bold))
                                .foregroundColor(.white)
                        }
                        .padding(.bottom, geometry.size.height * 0.05)
                        
                        Spacer()
                        
                        // Main content area
                        VStack(spacing: 30) {
                            // Start button
                            Button(action: {
                                showARView = true
                            }) {
                                Text("Start Translating")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding()
                                    .frame(width: min(geometry.size.width * 0.8, 280), height: 55)
                                    .background(Color.green)
                                    .cornerRadius(15)
                            }
                        }
                        
                        Spacer()
                        
                        // Footer
                        Text("Point your camera at a hand gesture")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .padding(.bottom, geometry.size.height * 0.05)
                    }
                    .padding(.horizontal)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .ignoresSafeArea(.all)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
