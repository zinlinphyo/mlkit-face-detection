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

class ViewController: UIViewController, FaceDetectionListener {
    
    @IBOutlet weak var cameraView: UIView!
    @IBOutlet weak var lblStatus: UILabel!
    @IBOutlet weak var instructionLabel: UILabel!
    
    private var cameraManager: FaceDetectCameraManager!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        cameraManager = FaceDetectCameraManager(viewController: self, previewView: cameraView, delegate: self)
        cameraManager.startCamera()
        cameraManager.startFaceDetection()
        cameraManager.requestNextFaceAction()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        cameraManager.updateLayout()
    }
    
    // Implement FaceDetectionListener methods
    func onNoFaceDetected(_ message: String) {
        lblStatus.text = message
        instructionLabel.text = "Position your face in the frame"
    }
    
    func onMultipleFaceDetected(_ message: String) {
        lblStatus.text = message
        instructionLabel.text = "Only one person allowed"
    }
    
    func onTooFarFaceDetected(_ message: String) {
        lblStatus.text = message
        instructionLabel.text = "Move closer to the camera"
    }
    
    func onRequestMessage(_ message: String) {
        lblStatus.text = message
        instructionLabel.text = message
    }
    
    func onActionCompleted(_ message: String) {
        lblStatus.text = message
        instructionLabel.text = "Great job!"
    }
    
    func onActionWrong(_ message: String) {
        lblStatus.text = message
        instructionLabel.text = message
    }
    
    func onDetectActionCompleted(_ message: String) {
        lblStatus.text = message
        instructionLabel.text = "All actions completed successfully!"
        // Enable photo button here
    }
    
    func onSuccessUpload(_ message: String) {
        lblStatus.text = message
        instructionLabel.text = "Photo captured successfully"
        // Handle successful photo capture
    }
    
    func onFailUpload(_ message: String) {
        lblStatus.text = message
        instructionLabel.text = "Failed to capture photo"
        // Handle failed photo capture
    }
    
    @IBAction func takePhotoTapped(_ sender: Any) {
        cameraManager.takePhoto()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cameraManager.stopCamera()
    }
}
