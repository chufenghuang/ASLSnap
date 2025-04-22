//
//  ARViewModel.swift
//  ASL Translator
//
//  Created by Chufeng Huang on 4/7/25.
//

import Foundation
import ARKit
import SceneKit
import Vision
import SwiftUI

/// Settings to control text display parameters
struct TextDisplaySettings {
    // Message bubble settings
    var bubbleWidth: CGFloat = 0.6       // Massively increased
    var bubbleHeight: CGFloat = 0.45     // Massively increased
    var bubbleDepth: CGFloat = 0.04      // Thicker for massive bubble
    var bubbleCornerRadius: CGFloat = 0.04 // Larger corners
    var bubbleColor = UIColor(red: 0.0, green: 0.5, blue: 0.9, alpha: 0.7)
    var bubbleTailHeight: CGFloat = 0.08  // Much larger tail
    
    // Text settings
    var textContent = "Hi, ASL Snap is here to help!"
    var textFontSize: CGFloat = 60       // Much larger font size
    var textColor = UIColor.white
    var textScale: SCNVector3 = SCNVector3(0.25, 0.25, 0.25)  // Much larger base scale
    
    // Position settings
    var verticalOffset: Float = -0.3     // Position much further from hand
    var depthOffset: Float = -0.25       // Further forward
    var movementSmoothing: Float = 0.3
    
    // Scale settings
    var baseScaleFactor: Float = 0.6     // Massively increased
    var minTextScale: Float = 0.03       // Much larger minimum
    var maxTextScale: Float = 0.1        // Much larger maximum
}

/// Represents a detected hand position in normalized coordinates
struct HandPosition {
    /// X coordinate in the camera view (0-1 normalized)
    let x: CGFloat
    
    /// Y coordinate in the camera view (0-1 normalized)
    let y: CGFloat
    
    /// Estimated depth from camera (when available)
    let depth: CGFloat?
    
    /// Confidence score of detection (0-1)
    let confidence: Float
}

/// Represents a text node displayed in AR
struct TextNode: Identifiable {
    /// Unique identifier for the text node
    let id: UUID
    
    /// Current position in view coordinates
    var position: CGPoint
    
    /// Text content displayed
    var text: String
    
    /// Whether node is currently visible
    var isVisible: Bool
}

/// The ViewModel (ObservableObject) that handles all ARKit & Vision logic.
class ARViewModel: NSObject, ObservableObject, ARSCNViewDelegate, ARSessionDelegate {
    
    // Reference to the ARSCNView (set after creation in ARViewContainer).
    private weak var sceneView: ARSCNView?
    
    // The node that highlights the hand in 3D space.
    private var handHighlightNode: SCNNode?
    
    // The node that displays "Hello" text
    private var helloTextNode: SCNNode?
    
    // Previous hand position for interpolation
    private var previousHandPosition: SCNVector3?
    
    // Track if the bubble has been positioned for the current hand detection
    private var isBubblePositioned = false
    
    // Interpolation factor (0 to 1, higher = faster movement)
    private let interpolationFactor: Float = 0.3
    
    // Settings for text display
    var textSettings = TextDisplaySettings()
    
    // Published properties for MVVM pattern
    @Published var handPositions: [HandPosition] = []
    @Published var textNodes: [TextNode] = []
    
    // Current hand distance in meters (z depth), used in prompt
    @Published var currentHandDistance: Float? = nil
    
    // Create a Vision request to detect one hand.
    private lazy var handPoseRequest: VNDetectHumanHandPoseRequest = {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 1
        return request
    }()
    
    // Published property to track if hand is detected
    @Published var isHandDetected = false
    
    // Track current camera position
    @Published var isFrontCameraActive = false
    
    // Threshold distance (meters) beyond which we ask the user to move closer
    private let distanceThreshold: Float = 0.2

    // Published property to show a move-closer prompt
    @Published var showMoveCloserPrompt: Bool = false
    
    /// Called by ARViewContainer after creating the ARSCNView.
    func setupScene(in sceneView: ARSCNView) {
        self.sceneView = sceneView
        sceneView.delegate = self
        sceneView.session.delegate = self
        
        // Enable occlusion so hands can visually block parts of the bubble
        sceneView.scene.rootNode.renderingOrder = -1 // Render scene first
        
        // Enable realistic lighting
        sceneView.automaticallyUpdatesLighting = true
        
        // Create an empty scene for ARSCNView.
        let scene = SCNScene()
        sceneView.scene = scene
        
        // Create and add the hello text node
        helloTextNode = createHelloTextNode()
        if let textNode = helloTextNode {
            scene.rootNode.addChildNode(textNode)
            // Initially hide the text until a hand is detected
            textNode.isHidden = true
        }
    }
    
    /// Create the AR session configuration and run it.
    func startSession() {
        guard let sceneView = sceneView else { return }
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        
        // Set camera position if device supports multiple cameras
        if ARWorldTrackingConfiguration.isSupported {
            // Front camera isn't directly supported in ARKit's standard configurations
            // We can only use what ARKit provides, which is typically the rear camera
            
            // Update UI to reflect actual capabilities
            if isFrontCameraActive {
                print("Front camera requested but not available in ARKit")
                // Revert to false since we can't actually use front camera
                DispatchQueue.main.async {
                    self.isFrontCameraActive = false
                }
            }
        }
        
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
    
    /// Toggles between front and rear camera
    func toggleCamera() {
        // Since ARKit doesn't directly support front camera for AR experiences,
        // we'll just toggle the variable but always use the rear camera
        isFrontCameraActive.toggle()
        startSession() // Restart session
    }
    
    // MARK: - ARSessionDelegate
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Convert the camera feed to a pixel buffer for Vision.
        let pixelBuffer = frame.capturedImage
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Perform the hand pose request.
                try handler.perform([self.handPoseRequest])
                
                // If a hand was detected, process it.
                if let results = self.handPoseRequest.results, !results.isEmpty {
                    if let observation = results.first {
                        // Access recognized points.
                        let recognizedPoints = try observation.recognizedPoints(.all)
                        
                        // Collect all hand points to calculate hand bounds
                        var handPoints: [CGPoint] = []
                        var minX: CGFloat = .infinity
                        var minY: CGFloat = .infinity
                        var maxX: CGFloat = 0
                        var maxY: CGFloat = 0
                        
                        // Collect all points with good confidence
                        for (_, point) in recognizedPoints {
                            if point.confidence > 0.3 {
                                // Convert normalized coordinates (0-1) to image space.
                                let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
                                let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
                                
                                let x = point.location.x * width
                                let y = (1.0 - point.location.y) * height
                                
                                handPoints.append(CGPoint(x: x, y: y))
                                
                                // Track min/max to find bounding box
                                minX = min(minX, x)
                                minY = min(minY, y)
                                maxX = max(maxX, x)
                                maxY = max(maxY, y)
                            }
                        }
                        
                        // Only proceed if we have enough points
                        if handPoints.count > 3 {
                            // Center of hand bounding box
                            let centerX = (minX + maxX) / 2
                            let centerY = (minY + maxY) / 2
                            let center = CGPoint(x: centerX, y: centerY)
                            
                            // Calculate hand size
                            let width = maxX - minX
                            let height = maxY - minY
                            let size = max(width, height) * 1.05 // Make highlight slightly larger than hand
                            
                            // Convert from 2D screen space to 3D AR space with hitTest.
                            guard let hits = self.sceneView?.hitTest(center, types: [.featurePoint]),
                                  let hit = hits.first else {
                                return
                            }
                            
                            let transform = hit.worldTransform
                            let position = SCNVector3(transform.columns.3.x,
                                                      transform.columns.3.y,
                                                      transform.columns.3.z)
                            
                            // Update the highlight node on main thread
                            DispatchQueue.main.async {
                                // Compute hand distance and store for UI
                                let handDistance = abs(position.z)
                                self.currentHandDistance = handDistance
                                // Show prompt if too far
                                self.showMoveCloserPrompt = handDistance > self.distanceThreshold
                                if self.showMoveCloserPrompt {
                                    // Hide bubble when too far
                                    self.helloTextNode?.isHidden = true
                                    // Skip bubble placement
                                    return
                                }

                                // If previously not detected, we're newly detecting a hand
                                let wasNotDetected = !self.isHandDetected
                                
                                self.isHandDetected = true
                                print("Hand detected at position: \(position), is highlight node nil? \(self.handHighlightNode == nil), is text node nil? \(self.helloTextNode == nil)")
                                
                                // Create and update HandPosition object
                                let handPosition = HandPosition(
                                    x: CGFloat(position.x),
                                    y: CGFloat(position.y),
                                    depth: CGFloat(position.z),
                                    confidence: 1.0
                                )
                                self.handPositions = [handPosition]
                                
                                // Update the size of the highlight based on hand size
                                let depthEstimate = abs(position.z)
                                // Increased base scaling factor for close-range detection
                                let worldSize = Float(0.0003) * Float(size) * depthEstimate
                                
                                // Make sure the nodes are visible and update their positions
                                self.handHighlightNode?.isHidden = true  // Always keep highlight hidden
                                self.handHighlightNode?.position = position
                                
                                // Update the highlight size with adjusted min/max for close range
                                let highlightScale = min(max(worldSize, 0.02), 0.06) // Increased minimums for better visibility
                                self.handHighlightNode?.scale = SCNVector3(highlightScale, highlightScale, highlightScale)
                                
                                // Update text visibility
                                self.helloTextNode?.isHidden = false
                                
                                // Only reposition the bubble if:
                                // 1. We just detected a hand for the first time
                                // 2. Or hand detection was lost and then regained
                                if wasNotDetected || !self.isBubblePositioned {
                                    // Calculate target position - adjusted to be far above the hand
                                    let targetPosition = SCNVector3(
                                        position.x,
                                        // Position far above the hand for the massive bubble
                                        position.y + highlightScale * self.textSettings.verticalOffset * 6.0, 
                                        position.z + self.textSettings.depthOffset * 1.5
                                    )
                                    
                                    // Place bubble directly at the target position
                                    self.helloTextNode?.position = targetPosition
                                    print("Bubble positioned at: \(targetPosition)")
                                    
                                    // Mark bubble as positioned
                                    self.isBubblePositioned = true
                                }
                                
                                // The bubble position is now fixed, so we don't update it when the hand moves
                                // This allows the hand to move in front of the bubble
                                
                                // Update previous position for other calculations
                                self.previousHandPosition = position
                                
                                // Create and update TextNode object for SwiftUI
                                if let worldPosition = self.helloTextNode?.position {
                                    // Convert 3D position to 2D screen coordinates
                                    if let screenPoint = self.sceneView?.projectPoint(worldPosition) {
                                        let textNode = TextNode(
                                            id: UUID(),
                                            position: CGPoint(x: CGFloat(screenPoint.x), y: CGFloat(screenPoint.y)),
                                            text: self.textSettings.textContent,
                                            isVisible: true
                                        )
                                        self.textNodes = [textNode]
                                    }
                                }
                                
                                // Scale the entire hello text node (bubble + text) based on distance
                                let textScale = min(max(worldSize * self.textSettings.baseScaleFactor, 
                                                       self.textSettings.minTextScale), 
                                                   self.textSettings.maxTextScale)
                                
                                // Apply a massively larger multiplier for giant bubble
                                let visibilityMultiplier: Float = 5.0
                                self.helloTextNode?.scale = SCNVector3(
                                    textScale * visibilityMultiplier,
                                    textScale * visibilityMultiplier,
                                    textScale * visibilityMultiplier
                                )
                                
                                print("Setting text scale to: \(textScale * visibilityMultiplier)")
                            }
                        }
                    }
                } else {
                    // No hand detected
                    DispatchQueue.main.async {
                        self.isHandDetected = false
                        self.handHighlightNode?.isHidden = true
                        self.helloTextNode?.isHidden = true
                        self.previousHandPosition = nil // Reset previous position when hand is lost
                        self.handPositions = [] // Clear hand positions
                        self.textNodes = [] // Clear text nodes
                        
                        // Reset bubble positioning flag so next detection will place a new bubble
                        self.isBubblePositioned = false
                        self.showMoveCloserPrompt = false
                        self.currentHandDistance = nil
                    }
                }
            } catch {
                print("Vision request error: \(error)")
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Updates the text content shown near the hand
    func updateTextContent(_ newText: String) {
        textSettings.textContent = newText
        
        // Recreate the text node with new content
        if let oldNode = helloTextNode {
            let position = oldNode.position
            oldNode.removeFromParentNode()
            
            helloTextNode = createHelloTextNode()
            if let newNode = helloTextNode {
                sceneView?.scene.rootNode.addChildNode(newNode)
                newNode.position = position
                newNode.isHidden = !isHandDetected
            }
        }
    }
    
    // MARK: - Utility
    
    /// Creates a node to highlight the hand
//    private func createHandHighlightNode() -> SCNNode {
//        // Create a semi-transparent box to highlight the hand
//        let box = SCNBox(width: 0.6, height: 0.6, length: 0.03, chamferRadius: 0.03)
//
//        // Create a material for the highlight
//        let material = SCNMaterial()
//        material.diffuse.contents = UIColor(red: 0.0, green: 0.7, blue: 0.3, alpha: 0.4)  // Brighter green
//        material.specular.contents = UIColor.white
//        material.emission.contents = UIColor(red: 0.0, green: 0.3, blue: 0.0, alpha: 0.2)  // Add subtle glow
//        material.isDoubleSided = true
//        box.materials = [material]
//
//        let node = SCNNode(geometry: box)
//        // Make the node always face the camera
//        node.constraints = [SCNBillboardConstraint()]
//        return node
//    }
    
    /// Creates a text node displaying a message bubble
    private func createHelloTextNode() -> SCNNode {
        // Create a parent node to handle positioning
        let parentNode = SCNNode()
        
        // Create message bubble
        let bubbleNode = createMessageBubble()
        parentNode.addChildNode(bubbleNode)
        
        // Create 3D text
        let textNode = createTextNode()
        
        // Position the text inside the bubble
        textNode.position = SCNVector3(0, 0, textSettings.bubbleDepth / 2 + 0.001)
        
        // Add text to bubble
        bubbleNode.addChildNode(textNode)
        
        // Add a subtle floating animation for AR feel
        let floatUp = SCNAction.moveBy(x: 0, y: 0.002, z: 0, duration: 1.0)
        let floatDown = SCNAction.moveBy(x: 0, y: -0.002, z: 0, duration: 1.0)
        let floatSequence = SCNAction.sequence([floatUp, floatDown])
        let floatForever = SCNAction.repeatForever(floatSequence)
        parentNode.runAction(floatForever)
        
        // Make everything always face the camera
        parentNode.constraints = [SCNBillboardConstraint()]
        
        print("Message bubble text node created")
        return parentNode
    }
    
    /// Creates a chat bubble shaped node
    private func createMessageBubble() -> SCNNode {
        // Create a rounded rectangle for the bubble
        let bubbleShape = SCNBox(
            width: textSettings.bubbleWidth,
            height: textSettings.bubbleHeight,
            length: textSettings.bubbleDepth,
            chamferRadius: textSettings.bubbleCornerRadius
        )
        
        // Create material for the bubble
        let bubbleMaterial = SCNMaterial()
        bubbleMaterial.diffuse.contents = textSettings.bubbleColor
        // Use constant lighting model for consistent appearance regardless of lighting
        bubbleMaterial.lightingModel = .constant
        bubbleMaterial.isDoubleSided = true
        
        // Apply material
        bubbleShape.materials = [bubbleMaterial]
        
        // Create bubble node
        let bubbleNode = SCNNode(geometry: bubbleShape)
        
        // Create the bubble tail (small triangle pointing down)
        let tailNode = createBubbleTail()
        tailNode.position = SCNVector3(0, -textSettings.bubbleHeight/2 - textSettings.bubbleTailHeight/2, 0)
        bubbleNode.addChildNode(tailNode)
        
        return bubbleNode
    }
    
    /// Creates the tail part of the message bubble
    private func createBubbleTail() -> SCNNode {
        // Create a triangular shape for the tail using a custom geometry
        let tailWidth = textSettings.bubbleWidth * 0.3
        let tailHeight = textSettings.bubbleTailHeight
        
        // Create a pyramid for the tail
        let tailGeometry = SCNCone(
            topRadius: 0.0,
            bottomRadius: tailWidth / 2,
            height: tailHeight
        )
        
        // Create material matching the bubble
        let tailMaterial = SCNMaterial()
        tailMaterial.diffuse.contents = textSettings.bubbleColor
        tailMaterial.lightingModel = .constant
        
        tailGeometry.materials = [tailMaterial]
        
        // Create tail node
        let tailNode = SCNNode(geometry: tailGeometry)
        tailNode.eulerAngles.x = Float.pi  // Flip it to point downward
        
        return tailNode
    }
    
    /// Creates the text node for the message
    private func createTextNode() -> SCNNode {
        // Create 3D text with updated content
        let text = SCNText(string: textSettings.textContent, extrusionDepth: 0.6) // Much thicker for massive text
        text.font = UIFont.systemFont(ofSize: textSettings.textFontSize, weight: .heavy) // Heaviest weight for maximum readability
        text.alignmentMode = CATextLayerAlignmentMode.center.rawValue
        text.chamferRadius = 0.0
        text.flatness = 0.001 // Highest quality for giant text
        
        // Create material for text with maximum visibility
        let textMaterial = SCNMaterial()
        textMaterial.diffuse.contents = UIColor.white
        textMaterial.emission.contents = UIColor.white
        textMaterial.lightingModel = .constant
        
        // Apply material
        text.firstMaterial = textMaterial
        
        // Create text node
        let textNode = SCNNode(geometry: text)
        
        // Center pivot point for text
        let (min, max) = text.boundingBox
        let dx = min.x + (max.x - min.x)/2
        let dy = min.y + (max.y - min.y)/2
        let dz = min.z + (max.z - min.z)/2
        textNode.pivot = SCNMatrix4MakeTranslation(dx, dy, dz)
        
        // Scale text to fit inside the massive bubble with proper proportion
        let textWidth = max.x - min.x
        let scaleFactor = (textSettings.bubbleWidth * 0.9) / CGFloat(textWidth) // Using 90% of the massive bubble
        textNode.scale = SCNVector3(scaleFactor, scaleFactor, scaleFactor)
        
        return textNode
    }
}
