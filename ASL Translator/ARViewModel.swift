//
//  ARViewModel.swift
//  ASL Translator AR Playground
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif
import SwiftUI
import ARKit
import SceneKit

class ARViewModel: NSObject, ObservableObject, ARSCNViewDelegate {
    private weak var sceneView: ARSCNView?
    private var windowNode: SCNNode?
    private let windowWidth: CGFloat = 2.0    // meters wide
    private let windowHeight: CGFloat = 0.8   // meters tall
    private let windowDepth: CGFloat = 0.05   // meters thick (increased for more visible volume)
    private let windowChamferRadius: CGFloat = 0.01 // rounded edges
    // Distance to push window further from camera (in meters)
    private let placementDistanceOffset: Float = 0.5
    
    // Subtitle properties
    private var subtitleTimer: Timer?
    private var subtitleIndex = 0
    private let subtitles: [String] = [
        "Welcome to the ASL Snap!",
        "This is a demo of dynamic translation.",
        "Text switches every few seconds.",
        "You can place and move windows.",
        "Enjoy this AR experience!"
    ]
    
    /// Text content to display on the window
    var textContent: String = "Hello ASL Snap"
    
    /// Called by ARViewContainer after creating the ARSCNView.
    func setupScene(in sceneView: ARSCNView) {
        self.sceneView = sceneView
        sceneView.delegate = self
        sceneView.automaticallyUpdatesLighting = true
        
        // Enable shadows by adding a directional light
        let lightNode = SCNNode()
        let light = SCNLight()
        light.type = .directional
        light.color = UIColor(white: 1.0, alpha: 1.0)
        light.castsShadow = true
        light.shadowMode = .deferred
        light.shadowSampleCount = 16
        light.shadowRadius = 15   // softer falloff
        light.shadowColor = UIColor(white: 0, alpha: 0.7) // darker shadow
        lightNode.light = light
        // Angle the light downwards
        lightNode.eulerAngles = SCNVector3(-Float.pi/3, Float.pi/4, 0)
        sceneView.scene.rootNode.addChildNode(lightNode)

        // Add a transparent ground plane to catch shadows
        let groundPlane = SCNPlane(width: 10, height: 10)
        let shadowMaterial = SCNMaterial()
        shadowMaterial.diffuse.contents = UIColor(white: 1.0, alpha: 0.0)
        shadowMaterial.lightingModel = .constant
        shadowMaterial.writesToDepthBuffer = true
        groundPlane.materials = [shadowMaterial]
        let groundNode = SCNNode(geometry: groundPlane)
        // Rotate horizontal and place at y=0
        groundNode.eulerAngles.x = -.pi/2
        sceneView.scene.rootNode.addChildNode(groundNode)
        
        // Add tap gesture for placing the AR window
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        sceneView.addGestureRecognizer(tapGesture)
    }
    
    /// Creates and runs the AR session configuration with plane detection.
    func startSession() {
        guard let sceneView = sceneView else { return }
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
    
    // MARK: - Tap Handling
    /// Handles user taps to place or move the AR window in world space
    @objc private func handleTap(_ sender: UITapGestureRecognizer) {
        guard let sceneView = sceneView else { return }
        let tapLocation = sender.location(in: sceneView)
        let hitResults = sceneView.hitTest(tapLocation, types: [.existingPlaneUsingExtent, .featurePoint])
        if let hit = hitResults.first {
                            let transform = hit.worldTransform
                            let position = SCNVector3(transform.columns.3.x,
                                                      transform.columns.3.y,
                                                      transform.columns.3.z)
                            
            // Remove any existing window
            windowNode?.removeFromParentNode()
            
            // Create and add new window at tapped position (offset further)
            let newWindow = createWindowNode()
            var adjustedPosition = position
            adjustedPosition.z -= placementDistanceOffset
            newWindow.position = adjustedPosition
            sceneView.scene.rootNode.addChildNode(newWindow)
            windowNode = newWindow
            startSubtitles()
        }
    }
    
    // MARK: - Node Creation
    /// Creates a 3D rectangular window with rounded edges and centers text inside
    private func createWindowNode() -> SCNNode {
        // Create a box for a more 3D look
        let box = SCNBox(
            width: windowWidth,
            height: windowHeight,
            length: windowDepth,
            chamferRadius: windowChamferRadius
        )
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(white: 1.0, alpha: 0.8)
        material.isDoubleSided = true
        box.materials = [material]

        let boxNode = SCNNode(geometry: box)

        // Create and add centered text on the front face
        let textNode = createTextNode(with: textContent)
        // Position text slightly left of center for visual centering on front face
        let zOffset = Float(windowDepth / 2.0 + 0.001)
        let xOffset = -Float(windowWidth * 0.05) // shift left by 5% of width
        textNode.position = SCNVector3(xOffset, 0, zOffset)
        boxNode.addChildNode(textNode)

        // Always face the camera
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .all
        boxNode.constraints = [billboard]

        // Scale text to fit inside the window
        let scaleFactor = Float(windowWidth * 0.3)
        textNode.scale = SCNVector3(scaleFactor, scaleFactor, scaleFactor)

        return boxNode
    }
    
    /// Creates a centered text node to display on the AR window
    private func createTextNode(with text: String) -> SCNNode {
        let scnText = SCNText(string: text, extrusionDepth: 0.02)
        scnText.font = UIFont.systemFont(ofSize: 0.15, weight: .bold)
        scnText.alignmentMode = CATextLayerAlignmentMode.center.rawValue
        scnText.firstMaterial?.diffuse.contents = UIColor.black
        
        let textNode = SCNNode(geometry: scnText)
        // Center the pivot to center the text geometry
        let (min, max) = scnText.boundingBox
        let dx = min.x + (max.x - min.x)/2
        let dy = min.y + (max.y - min.y)/2
        let dz = min.z + (max.z - min.z)/2
        textNode.pivot = SCNMatrix4MakeTranslation(dx, dy, dz)
        
        return textNode
    }
    
    // MARK: - Text Updates
    /// Updates the text content on the AR window if already placed
    func updateTextContent(_ newText: String) {
        textContent = newText
        if let window = windowNode,
           let textNode = window.childNodes.first(where: { $0.geometry is SCNText }),
           let scnText = textNode.geometry as? SCNText {
            scnText.string = newText
        }
    }
    
    // MARK: - Subtitle Cycling
    private func startSubtitles() {
        subtitleTimer?.invalidate()
        subtitleIndex = 0
        DispatchQueue.main.async {
            self.updateTextContent(self.subtitles[self.subtitleIndex])
        }
        subtitleTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.showNextSubtitle()
        }
    }
    
    private func showNextSubtitle() {
        subtitleIndex = (subtitleIndex + 1) % subtitles.count
        DispatchQueue.main.async {
            self.updateTextContent(self.subtitles[self.subtitleIndex])
        }
    }
    
    /// Place the AR window at the center of the screen
    func placeWindowAtCenter() {
        guard let sceneView = sceneView else { return }
        let center = CGPoint(x: sceneView.bounds.midX, y: sceneView.bounds.midY)
        let hitResults = sceneView.hitTest(center, types: [.existingPlaneUsingExtent, .featurePoint])
        if let hit = hitResults.first {
            let transform = hit.worldTransform
            let position = SCNVector3(transform.columns.3.x,
                                      transform.columns.3.y,
                                      transform.columns.3.z)
            windowNode?.removeFromParentNode()
            let newWindow = createWindowNode()
            var adjustedPosition = position
            adjustedPosition.z -= placementDistanceOffset
            newWindow.position = adjustedPosition
            sceneView.scene.rootNode.addChildNode(newWindow)
            windowNode = newWindow
            startSubtitles()
        }
    }
}
