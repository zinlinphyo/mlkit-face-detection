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
    @IBOutlet weak var takePhotoButton: UIButton!
    @IBOutlet weak var capturedImageView: UIImageView!
    
    private var cameraManager: FaceDetectCameraManager!
    private var isPhotoTaken = false
    
    override func viewDidLoad() {
        super.viewDidLoad()

        cameraManager = FaceDetectCameraManager(viewController: self, previewView: cameraView, delegate: self)
        cameraManager.startCamera()
        cameraManager.startFaceDetection()
        cameraManager.requestNextFaceAction()

        capturedImageView.isHidden = true // Initially hide the image view
        updateTakePhotoButton()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        cameraManager.updateLayout()
    }
    
    private func updateTakePhotoButton() {
        let title = isPhotoTaken ? "Retry" : "Take Photo"
        takePhotoButton.setTitle(title, for: .normal)
        takePhotoButton.isEnabled = isPhotoTaken || cameraManager.completedActions >= cameraManager.requiredAction
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
        updateTakePhotoButton()
    }
    
    func onSuccessUpload(_ message: String, image: UIImage?) {
        lblStatus.text = message
        instructionLabel.text = "Photo captured successfully"
        isPhotoTaken = true
        updateTakePhotoButton()

        // Show the captured image
        capturedImageView.image = image
        capturedImageView.isHidden = false
    }
    
    func onFailUpload(_ message: String) {
        lblStatus.text = message
        instructionLabel.text = "Failed to capture photo"
        // Optionally, keep isPhotoTaken = false
        updateTakePhotoButton()
    }
    
    @IBAction func takePhotoTapped(_ sender: Any) {
        if isPhotoTaken {
            // Reset all actions and UI
            isPhotoTaken = false
            cameraManager.resetLiveness()
            cameraManager.startFaceDetection()
            cameraManager.requestNextFaceAction()
            lblStatus.text = "Follow the instructions"
            instructionLabel.text = "Position your face in the frame"
            updateTakePhotoButton()

            // Reset UI
            capturedImageView.image = nil
            capturedImageView.isHidden = true
        } else {
            cameraManager.takePhoto()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cameraManager.stopCamera()
    }
}
