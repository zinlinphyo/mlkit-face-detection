//
//  FaceDetectionManager.swift
//  mlkit-test
//
//  Created by Zin Lin Phyo on 2/5/25.
//

import UIKit
import AVFoundation
import MLKitFaceDetection
import MLKitVision

// Protocol equivalent to the FaceDetectionListener interface
protocol FaceDetectionListener: AnyObject {
    func onNoFaceDetected(_ message: String)
    func onMultipleFaceDetected(_ message: String)
    func onTooFarFaceDetected(_ message: String)
    func onRequestMessage(_ message: String)
    func onActionCompleted(_ message: String)
    func onActionWrong(_ message: String)
    func onDetectActionCompleted(_ message: String)
    func onSuccessUpload(_ message: String)
    func onFailUpload(_ message: String)
}

// Enum for face actions
enum FaceAction {
    case smile
    case headShake
    case blink
    case headNod
}

class FaceDetectCameraManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private weak var viewController: UIViewController?
    private weak var previewView: UIView?
    private weak var delegate: FaceDetectionListener?
    
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var imageOutput: AVCapturePhotoOutput?
    
    private var currentAction: FaceAction?
    private var actionCompleted = false
    private var completedActions = 0
    private let requiredAction = 3
    
    private var currentStep = 1
    private var isFaceDetectionActive = false
    
    // For head nodding detection
    private var headPitchHistory: [Float] = []
    private var lastPitchDirection: Bool? = nil // true = up, false = down
    private var pitchDirectionChanges = 0
    private let requiredDirectionChanges = 3
    private let headNodThreshold: Float = 10.0 // degrees
    
    private lazy var faceDetector: FaceDetector = {
        let options = FaceDetectorOptions()
        options.performanceMode = .fast
        options.landmarkMode = .all
        options.classificationMode = .all
        options.isTrackingEnabled = true
        return FaceDetector.faceDetector(options: options)
    }()
    
    init(viewController: UIViewController, previewView: UIView, delegate: FaceDetectionListener) {
        self.viewController = viewController
        self.previewView = previewView
        self.delegate = delegate
        super.init()
    }
    
    func startCamera() {
        captureSession = AVCaptureSession()
        
        guard let captureSession = captureSession else { return }
        
        // Configure camera input
        guard let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            print("Front camera not available")
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: frontCamera)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }
            
            // Configure video output
            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
            if captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)
            }
            
            // Configure photo output
            imageOutput = AVCapturePhotoOutput()
            if let imageOutput = imageOutput, captureSession.canAddOutput(imageOutput) {
                captureSession.addOutput(imageOutput)
            }
            
            // Configure preview layer
            guard let previewView = previewView else { return }
            previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer?.frame = previewView.bounds
            previewLayer?.videoGravity = .resizeAspectFill
            previewLayer?.connection?.automaticallyAdjustsVideoMirroring = false
            previewLayer?.connection?.isVideoMirrored = true
            
            if let previewLayer = previewLayer {
                previewView.layer.insertSublayer(previewLayer, at: 0)
            }
            
            // Start capture session
            DispatchQueue.global(qos: .userInitiated).async {
                captureSession.startRunning()
            }
            
        } catch {
            print("Error setting up camera: \(error)")
        }
    }
    
    func startFaceDetection() {
        isFaceDetectionActive = true
    }
    
    func stopFaceDetection() {
        isFaceDetectionActive = false
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if !isFaceDetectionActive {
            return
        }
        
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let visionImage = VisionImage(buffer: sampleBuffer)
        visionImage.orientation = imageOrientation()
        
        faceDetector.process(visionImage) { [weak self] faces, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Face detection error: \(error.localizedDescription)")
                return
            }
            
            DispatchQueue.main.async {
                if let faces = faces {
                    self.handleFaceFlow(faces: faces)
                }
            }
        }
    }
    
    private func handleFaceFlow(faces: [Face]) {
        switch currentStep {
        case 1:
            if faces.isEmpty {
                delegate?.onNoFaceDetected("No face detected. Please move into the frame.")
            } else {
                currentStep += 1
            }
            
        case 2:
            if faces.isEmpty {
                currentStep = 1
            } else if faces.count > 1 {
                delegate?.onMultipleFaceDetected("Multiple faces detected. Only one person allowed.")
            } else {
                currentStep += 1
            }
            
        case 3:
            if faces.isEmpty {
                currentStep = 1
            } else if faces.count > 1 {
                currentStep = 2
            } else {
                currentStep += 1
            }
            
        case 4:
            if faces.isEmpty {
                currentStep = 1
            } else if faces.count > 1 {
                currentStep = 2
            } else {
                let face = faces.first!
                if isFaceTooFar(face: face) {
                    let targetDistance = "Please come to 1 meter"
                    delegate?.onTooFarFaceDetected("You are too far. \(targetDistance)")
                } else {
                    currentStep += 1
                }
            }
            
        case 5:
            if faces.isEmpty {
                currentStep = 1
            } else if faces.count > 1 {
                currentStep = 2
            } else {
                let face = faces.first!
                
                if isFaceTooFar(face: face) {
                    currentStep = 4
                } else {
                    goToRandomAction(face: face)
                }
            }
            
        default:
            break
        }
    }
    
    private func isFaceTooFar(face: Face) -> Bool {
        let distanceMeters = estimateDistanceFromFace(face: face)
        return distanceMeters > 1.5
    }
    
    private func estimateDistanceFromFace(face: Face) -> Float {
        // Convert face bounding box to view coordinates
        guard let previewLayer = previewLayer else { return 0 }
        let faceRect = previewLayer.layerRectConverted(fromMetadataOutputRect: face.frame)
        
        let area = Float(faceRect.width * faceRect.height)
        let referenceArea: Float = 50000 // area when face is 0.5 meters away
        let referenceDistance: Float = 0.5 // meters
        
        return referenceArea / area * referenceDistance
    }
    
    func requestNextFaceAction() {
        // Randomly select next action
        let actions: [FaceAction] = [.smile, .headShake, .blink, .headNod]
        currentAction = actions.randomElement()
        actionCompleted = false
        
        // Reset head nodding detection
        headPitchHistory.removeAll()
        lastPitchDirection = nil
        pitchDirectionChanges = 0
    }
    
    private func goToRandomAction(face: Face) {
        if actionCompleted { return }
        
        let leftEyeOpenProb = face.leftEyeOpenProbability ?? 1.0
        let rightEyeOpenProb = face.rightEyeOpenProbability ?? 1.0
        let smilingProb = face.smilingProbability ?? 0.0
        let headYaw = face.headEulerAngleY // Left/Right
        let headPitch = face.headEulerAngleX // Up/Down
        
        switch currentAction {
        case .smile:
            if smilingProb > 0.7 {
                onActionCompleted(message: "Detected: Smile")
            } else {
                delegate?.onRequestMessage("Please smile 😊.")
            }
            
        case .headShake:
            if abs(headYaw) > 15 {
                onActionCompleted(message: "Detected: Head shake (left ↔ right)")
            } else {
                delegate?.onRequestMessage("Please shake your head left ↔ right 🙆.")
            }
            
        case .blink:
            if leftEyeOpenProb == 0.0 || rightEyeOpenProb == 0.0 {
                onActionCompleted(message: "Detected: Blink")
            } else {
                delegate?.onRequestMessage("Please blink your eyes 😉.")
            }
            
        case .headNod:
            detectHeadNod(headPitch: Float(headPitch))
            if !actionCompleted {
                delegate?.onRequestMessage("Please nod your head up and down 🙂.")
            }
            
        case .none:
            // Default to smile if no action is set
            if smilingProb > 0.7 {
                onActionCompleted(message: "Detected: Smile")
            } else {
                delegate?.onRequestMessage("Please smile 😊.")
            }
        }
    }
    
    private func detectHeadNod(headPitch: Float) {
        // Add current pitch to history
        headPitchHistory.append(headPitch)
        
        // Keep only recent history
        if headPitchHistory.count > 10 {
            headPitchHistory.removeFirst()
        }
        
        // Need at least 3 samples to detect direction changes
        if headPitchHistory.count < 3 {
            return
        }
        
        // Detect direction changes (up to down or down to up)
        for i in 2..<headPitchHistory.count {
            let prev = headPitchHistory[i-1]
            let current = headPitchHistory[i]
            
            // Check if significant movement
            if abs(current - prev) > 3.0 {
                let isMovingUp = current < prev // Note: pitch decreases when looking up
                
                // If direction changed
                if lastPitchDirection != nil && isMovingUp != lastPitchDirection! {
                    pitchDirectionChanges += 1
                    
                    // Debug
                    print("Direction change detected: \(pitchDirectionChanges)")
                }
                
                lastPitchDirection = isMovingUp
            }
        }
        
        // Check if we've detected enough direction changes for a nod
        if pitchDirectionChanges >= requiredDirectionChanges {
            onActionCompleted(message: "Detected: Head nod (up ↕ down)")
        }
    }
    
    private func onActionCompleted(message: String) {
        delegate?.onActionCompleted(message)
        actionCompleted = true
        completedActions += 1
        
        if completedActions >= requiredAction {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.delegate?.onDetectActionCompleted("All done! Let's take a photo.")
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                self?.requestNextFaceAction()
            }
        }
    }
    
    func takePhoto() {
        guard let imageOutput = imageOutput, captureSession?.isRunning == true else {
            delegate?.onFailUpload("Camera not ready")
            return
        }
        
        let settings = AVCapturePhotoSettings()
        imageOutput.capturePhoto(with: settings, delegate: self)
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
    
    func stopCamera() {
        captureSession?.stopRunning()
        stopFaceDetection()
    }
    
    func resetLiveness() {
        completedActions = 0
        currentAction = nil
        actionCompleted = false
        currentStep = 1
        headPitchHistory.removeAll()
        lastPitchDirection = nil
        pitchDirectionChanges = 0
    }
    
    func updateLayout() {
        guard let previewView = previewView else { return }
        previewLayer?.frame = previewView.bounds
    }
}

// Extension to handle photo capture
extension FaceDetectCameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            delegate?.onFailUpload("Photo capture failed: \(error.localizedDescription)")
            return
        }
        
        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            delegate?.onFailUpload("Failed to process captured photo")
            return
        }
        
        // Save photo to temporary file
        let fileURL = saveImageToTemporaryFile(image: image)
        
        if let fileURL = fileURL {
            delegate?.onSuccessUpload("Photo capture succeed")
        } else {
            delegate?.onFailUpload("Photo capture failed")
        }
    }
    
    private func saveImageToTemporaryFile(image: UIImage) -> URL? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let fileName = "\(dateFormatter.string(from: Date())).jpg"
        
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            return nil
        }
        
        do {
            try imageData.write(to: fileURL)
            return fileURL
        } catch {
            print("Error saving image: \(error)")
            return nil
        }
    }
}
