//
//  ViewController.swift
//  mlkit-test
//
//  Created by Zin Lin Phyo on 28/4/25.
//

import UIKit
import AVFoundation
import MLKitFaceDetection
import MLKitVision

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {

    @IBOutlet weak var cameraView: UIView!
    @IBOutlet weak var lblStatus: UILabel!
    @IBOutlet weak var instructionLabel: UILabel!
    
    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private let overlayLayer = CAShapeLayer()
    
    // Liveness verification properties
    private enum LivenessState {
        case waitingForFace
        case waitingForBlink
        case waitingForSmile
        case waitingForNod
        case livenessVerified
    }
    
    private var currentState: LivenessState = .waitingForFace
    private var blinkDetected = false
    private var smileDetected = false
    private var nodDetected = false
    
    // For tracking head movement
    private var previousFacePosition: CGPoint?
    private var faceMoves: [CGPoint] = []
    private var lastStateChangeTime = Date()
    
    // For tracking blinks
    private var eyesWereOpen = false
    private var blinkStartTime: Date?
    
    private lazy var faceDetector: FaceDetector = {
        let options = FaceDetectorOptions()
        options.performanceMode = .fast // Try faster mode first
        options.landmarkMode = .all
        options.classificationMode = .all
        options.minFaceSize = 0.1 // Lower threshold to detect smaller faces
        options.isTrackingEnabled = true // Enable tracking for better performance
        return FaceDetector.faceDetector(options: options)
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        
        instructionLabel.text = "TEST - Is this visible?"
        instructionLabel.textColor = .red
        instructionLabel.backgroundColor = .yellow
        
        setupUI()
        setupCamera()
        updateInstructionLabel()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        debugLabelVisibility()
    }

    func debugLabelVisibility() {
        if instructionLabel.superview == nil {
            print("⚠️ Label has no superview - not in hierarchy!")
        } else {
            print("✅ Label is in view hierarchy")
            print("Label frame: \(instructionLabel.frame)")
            print("Is hidden: \(instructionLabel.isHidden)")
            print("Alpha: \(instructionLabel.alpha)")
        }
    }

    func setupUI() {
        // Setup overlay (square frame inside cameraView)
        overlayLayer.strokeColor = UIColor.systemTeal.cgColor
        overlayLayer.lineWidth = 3
        overlayLayer.fillColor = UIColor.clear.cgColor
        overlayLayer.lineJoin = .round
        cameraView.layer.addSublayer(overlayLayer)
        
        drawSquareOverlay()
        
    }

    func setupCamera() {
        guard let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            print("Front camera not available.")
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: frontCamera)
            captureSession.addInput(input)

            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
            captureSession.addOutput(videoOutput)

            previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer.frame = cameraView.bounds
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.connection?.automaticallyAdjustsVideoMirroring = false
            previewLayer.connection?.isVideoMirrored = true

            cameraView.layer.insertSublayer(previewLayer, at: 0)

            DispatchQueue.global(qos: .userInitiated).async {
                self.captureSession.startRunning()
            }
        } catch {
            print("Error setting up front camera: \(error)")
        }
    }

    private func drawSquareOverlay() {
        let squarePath = UIBezierPath(roundedRect: cameraView.bounds.insetBy(dx: 10, dy: 10), cornerRadius: 16)
        overlayLayer.path = squarePath.cgPath
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = cameraView.bounds
        drawSquareOverlay()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        detectFaces(sampleBuffer: sampleBuffer)
    }

    private func detectFaces(sampleBuffer: CMSampleBuffer) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("Failed to get image buffer from sample buffer")
            return
        }

        let visionImage = VisionImage(buffer: sampleBuffer)
        visionImage.orientation = imageOrientation()

        // Print orientation for debugging
        print("Current image orientation: \(visionImage.orientation.rawValue)")

        faceDetector.process(visionImage) { [weak self] faces, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Face detection error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.lblStatus.text = "Detection error"
                }
                return
            }
            
            print("Face detection completed. Faces found: \(faces?.count ?? 0)")
            
            guard let faces = faces, !faces.isEmpty else {
                DispatchQueue.main.async {
                    self.lblStatus.text = "No face detected"
                    self.currentState = .waitingForFace
                    self.previousFacePosition = nil
                    self.updateInstructionLabel()
                }
                return
            }

            // Get the most prominent face
            let face = faces.first!
            
            DispatchQueue.main.async {
                let faceFrameInView = self.previewLayer.layerRectConverted(fromMetadataOutputRect: face.frame)
                let faceCenterInView = CGPoint(x: faceFrameInView.midX, y: faceFrameInView.midY)
                
                if self.isFaceInsideSquare(faceFrame: faceFrameInView) {
                    // Process liveness based on current state
                    switch self.currentState {
                    case .waitingForFace:
                        self.lblStatus.text = "✅ Face detected"
                        self.currentState = .waitingForBlink
                        self.lastStateChangeTime = Date()
                        
                    case .waitingForBlink:
                        self.detectBlink(face: face)
                        
                    case .waitingForSmile:
                        self.detectSmile(face: face)
                        
                    case .waitingForNod:
                        self.detectHeadMovement(faceCenterPoint: faceCenterInView)
                        
                    case .livenessVerified:
                        self.lblStatus.text = "✅ Liveness Verified"
                    }
                } else {
                    self.lblStatus.text = "❌ Center face in frame"
                }
                
                self.updateInstructionLabel()
            }
        }
    }
    
    private func detectBlink(face: Face) {
        // Check if we can access eye properties
        if face.hasLeftEyeOpenProbability && face.hasRightEyeOpenProbability {
            let leftEyeOpenProbability = face.leftEyeOpenProbability
            let rightEyeOpenProbability = face.rightEyeOpenProbability
            
            let eyesOpen = leftEyeOpenProbability > 0.9 && rightEyeOpenProbability > 0.9
            let eyesClosed = leftEyeOpenProbability < 0.1 && rightEyeOpenProbability < 0.1
            
            if !blinkDetected {
                if eyesWereOpen && eyesClosed {
                    // Eyes just closed
                    blinkStartTime = Date()
                } else if let startTime = blinkStartTime, eyesOpen {
                    // Complete blink detected
                    let blinkDuration = Date().timeIntervalSince(startTime)
                    
                    // Natural blink is typically 0.1-0.4 seconds
                    if blinkDuration > 0.1 && blinkDuration < 0.4 {
                        blinkDetected = true
                        currentState = .waitingForSmile
                        lastStateChangeTime = Date()
                    }
                    blinkStartTime = nil
                }
            }
            
            eyesWereOpen = eyesOpen
            lblStatus.text = blinkDetected ? "✅ Blink detected!" : "Waiting for blink..."
        } else {
            lblStatus.text = "Cannot detect eyes"
        }
    }
    
    private func detectSmile(face: Face) {
        if face.hasSmilingProbability {
            let smilingProbability = face.smilingProbability
            
            if smilingProbability > 0.8 {
                smileDetected = true
                currentState = .waitingForNod
                lastStateChangeTime = Date()
            }
            
            lblStatus.text = smileDetected ? "✅ Smile detected!" : "Waiting for smile..."
        } else {
            lblStatus.text = "Cannot detect smile"
        }
    }
    
    private func detectHeadMovement(faceCenterPoint: CGPoint) {
        // Store face position for tracking movement
        if let previousPosition = previousFacePosition {
            // Calculate movement
            let distance = hypot(faceCenterPoint.x - previousPosition.x, faceCenterPoint.y - previousPosition.y)
            
            // If significant movement detected
            if distance > 5 {
                faceMoves.append(faceCenterPoint)
                
                // Keep only recent movements for analysis
                if faceMoves.count > 10 {
                    faceMoves.removeFirst()
                }
                
                // Detect nodding (vertical movement pattern)
                if faceMoves.count >= 6 {
                    var verticalChanges = 0
                    var isMovingDown = faceMoves[1].y > faceMoves[0].y
                    
                    for i in 1..<faceMoves.count {
                        let currentIsMovingDown = faceMoves[i].y > faceMoves[i-1].y
                        if currentIsMovingDown != isMovingDown {
                            verticalChanges += 1
                            isMovingDown = currentIsMovingDown
                        }
                    }
                    
                    // Detect nodding with at least 3 direction changes
                    if verticalChanges >= 3 {
                        nodDetected = true
                        currentState = .livenessVerified
                    }
                }
            }
        }
        
        previousFacePosition = faceCenterPoint
        lblStatus.text = nodDetected ? "✅ Head nod detected!" : "Waiting for head nod..."
    }

    private func isFaceInsideSquare(faceFrame: CGRect) -> Bool {
        let squareFrame = cameraView.bounds.insetBy(dx: 10, dy: 10)
        let faceCenterPoint = CGPoint(x: faceFrame.midX, y: faceFrame.midY)
        return squareFrame.contains(faceCenterPoint) &&
               faceFrame.width < squareFrame.width &&
               faceFrame.height < squareFrame.height
    }

    private func imageOrientation() -> UIImage.Orientation {
        switch UIDevice.current.orientation {
        case .portrait:
            return .right
        case .landscapeLeft:
            return .up
        case .portraitUpsideDown:
            return .left
        case .landscapeRight:
            return .down
        default:
            return .right
        }
    }
    
    private func updateInstructionLabel() {
        let instruction: String
        
        switch currentState {
        case .waitingForFace:
            instruction = "Position your face in the frame"
        case .waitingForBlink:
            instruction = "Please blink both eyes once"
        case .waitingForSmile:
            instruction = "Now, please smile"
        case .waitingForNod:
            instruction = "Nod your head up and down"
        case .livenessVerified:
            instruction = "Verification complete! ✅"
        }
        
        // Show timeout message if a state takes too long
        let timeInCurrentState = Date().timeIntervalSince(lastStateChangeTime)
        if timeInCurrentState > 10 && currentState != .livenessVerified && currentState != .waitingForFace {
            instructionLabel.text = "\(instruction) (Timeout: \(Int(10 - timeInCurrentState)) sec)"
        } else {
            instructionLabel.text = instruction
        }
        
        // Make absolutely sure the label is visible
        instructionLabel.isHidden = false
        instructionLabel.alpha = 1.0
    }
    
    // Add this method to reset the verification if needed
    func resetLivenessDetection() {
        currentState = .waitingForFace
        blinkDetected = false
        smileDetected = false
        nodDetected = false
        previousFacePosition = nil
        faceMoves.removeAll()
        lastStateChangeTime = Date()
        updateInstructionLabel()
    }
}

extension CGRect {
    func normalized(width: CGFloat, height: CGFloat) -> CGRect {
        return CGRect(
            x: origin.x / width,
            y: origin.y / height,
            width: size.width / width,
            height: size.height / height
        )
    }
}
