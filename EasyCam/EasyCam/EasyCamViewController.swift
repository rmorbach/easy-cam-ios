//
//  EasyCamViewController.swift
//  EasyCam
//
//  Created by Rodrigo Morbach on 12/07/18.
//  Copyright © 2018 Morbach Inc. All rights reserved.
//

import UIKit
import AVFoundation

@objc public protocol EasyCamDelegate : NSObjectProtocol {
    /**
     This method will be called in the main queue.
    */
    func easyCamDidFail(error : Error)
    /**
     If implemented, this method will be called in a serial thread
     */
    @objc optional func easyCamDidCapture(image: UIImage);
    /**
     If implemented, this method will be called in a serial thread
     */
    @objc optional func easyCamDidCapture(sampleBuffer: CMSampleBuffer);
    /**
     If implemented, this method will be called in a serial thread
     */
    @objc optional func easyCamDidCaptureStill(image: UIImage);
}

public enum EasyCamError : Error {
    case runTimeError(String)
    case camSetupError(String)
}

public struct EasyCamCaptureSettings {
    
    public enum VideoGravity : String {
        case resizeAspect = "AVLayerVideoGravityResizeAspect"
        case resizeAspectFill = "AVLayerVideoGravityResizeAspectFill"
        case resize = "AVLayerVideoGravityResize"
    }
    
    public let cameraPosition : AVCaptureDevice.Position
    /**
     A constant value indicating the quality level or bitrate of the output.
    */
    public let sessionPreset : AVCaptureSession.Preset?
    /**
    Defines how the video is displayed within an AVCaptureVideoPreviewLayer bounds rect.
    */
    public let videoGravity: VideoGravity
    
    public init(cameraPosition: AVCaptureDevice.Position, sessionPreset: AVCaptureSession.Preset?, videoGravity: VideoGravity?) {
        self.cameraPosition = cameraPosition
        self.sessionPreset = sessionPreset;
        if videoGravity == nil {
            self.videoGravity = .resizeAspect
        } else {
            self.videoGravity = videoGravity!
        }
    }
    
}

public class EasyCamViewController: UIViewController {
    
    public weak var delegate : EasyCamDelegate?
    
    private let delegateQueue = DispatchQueue(label: "delegate queue", qos: DispatchQoS.default, attributes: [], autoreleaseFrequency: DispatchQueue.AutoreleaseFrequency.inherit, target: nil)
    
    private let semaphore = DispatchSemaphore(value: 2);
    
    private let session = AVCaptureSession()
    
    private var sessionIsRunning = false;
    
    private let videoDeviceOutput = AVCaptureVideoDataOutput()
    
    private var videoDeviceInput : AVCaptureDeviceInput!
    
    private var hasMultipleCameras = false;
    
    public var captureSettings : EasyCamCaptureSettings? {
        get {
            return captureVideoSettings
        }
    }
    
    private var captureVideoSettings : EasyCamCaptureSettings?
    
    private var frameView = Bundle(for: EasyCamViewController.self).loadNibNamed("EasyCamFrameView", owner: self, options: nil)?.first as! EasyCamFrameView
    
    private let sessionQueue = DispatchQueue(label: "session queue", qos: DispatchQoS.default, attributes: [], autoreleaseFrequency: DispatchQueue.AutoreleaseFrequency.inherit, target: nil)
    
    private let mainQueue = DispatchQueue.main;
    
    private enum SessionSetupResult {
        case success, notAuthorized, failed;
    }
    
    private var sessionSetup : SessionSetupResult = .failed;
    
    //KVO and Observers
    private var keyValueObservations = [NSKeyValueObservation]()
    
    
    public convenience init(captureSettings: EasyCamCaptureSettings?) {
        self.init()
        self.captureVideoSettings = captureSettings
    }
    
    public convenience init(frameView : EasyCamFrameView, captureSettings: EasyCamCaptureSettings?) {
        self.init()
        self.frameView = frameView
        self.captureVideoSettings = captureSettings
    }
    
    override public func viewDidLoad() {
        super.viewDidLoad()
        
        //Check if preview view available
        assert((self.frameView.previewView != nil), "Please add a EasyCamPreviewView to your EasyCamFrameView instance")
        
        self.frameView.easyCamControlDelegate = self;
        
        let previewFrame = CGRect(origin: self.view.frame.origin, size: self.view.frame.size)
        
        self.frameView.frame = previewFrame
        
        self.view.addSubview(self.frameView);
        
        self.view.bringSubview(toFront: self.frameView)
        
        self.frameView.previewView.session = self.session
        
        self.frameView.previewView.videoPreviewLayer.videoGravity = AVLayerVideoGravity(rawValue: self.captureVideoSettings!.videoGravity.rawValue)
        
        self.sessionQueue.async {
            self.configureSession()
        }

        // Do any additional setup after loading the view.
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        self.sessionQueue.async {
        
            switch self.sessionSetup {
            case .success:
                debugPrint("success")
                self.addObservers()
                self.session.startRunning()
                self.sessionIsRunning = self.session.isRunning
            case .notAuthorized:
                debugPrint("notAuthorized")
                self.mainQueue.async {
                    self.delegate?.easyCamDidFail(error: EasyCamError.camSetupError("Permission denied to access camera"))
                }
            case .failed:
                debugPrint("failed")
                self.mainQueue.async {
                    self.delegate?.easyCamDidFail(error: EasyCamError.camSetupError("Failed setting up camera"))
                }
            }
            
        }
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        if sessionIsRunning {
            self.sessionQueue.async {
                self.session.stopRunning()
                self.removeObservers()
            }
        }
    }
    
    private func configureSession() {
        
        self.session.beginConfiguration()
        
        let cameraPosition = self.captureSettings != nil ? self.captureSettings!.cameraPosition : AVCaptureDevice.Position.back;
        
        guard let device = EasyCamViewController.device(with: .video, preferringPosition: cameraPosition) else {
            return
        }
        
        do {
            let videoDeviceInput = try AVCaptureDeviceInput(device: device)
           
            self.videoDeviceOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as AnyHashable as! String: NSNumber(value: kCVPixelFormatType_32BGRA)]
            
            self.videoDeviceOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)
            
            if session.canAddOutput(self.videoDeviceOutput) {
                
                self.session.addOutput(self.videoDeviceOutput)
                
            } else {
                debugPrint("could not add device input to the session")
            }
            
            if session.canAddInput(videoDeviceInput) {
                self.session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput;
            } else {
                debugPrint("could not add device output to the session")
            }
            
            if let customSessionPreset = self.captureVideoSettings?.sessionPreset {
                if self.session.canSetSessionPreset(customSessionPreset) {
                    self.session.sessionPreset = customSessionPreset
                }
            }
            
            mainQueue.async {
                
                /*
                 Why are we dispatching this to the main queue?
                 Because AVCaptureVideoPreviewLayer is the backing layer for PreviewView and UIView
                 can only be manipulated on the main thread.
                 Note: As an exception to the above rule, it is not necessary to serialize video orientation changes
                 on the AVCaptureVideoPreviewLayer’s connection with other session manipulation.
                 
                 Use the status bar orientation as the initial video orientation. Subsequent orientation changes are
                 handled by CameraViewController.viewWillTransition(to:with:).
                 */
                let initialOrientation = AVCaptureVideoOrientation.portrait;
                self.frameView.previewView.videoPreviewLayer.connection?.videoOrientation = initialOrientation;
            }
            
        } catch  {
            sessionSetup = .failed;
            self.session.commitConfiguration()
        }
        
        self.sessionSetup = .success
        self.session.commitConfiguration()
    }
    
    override public func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

}

extension EasyCamViewController : AVCaptureVideoDataOutputSampleBufferDelegate {
    
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        semaphore.wait()
        
        debugPrint("captureOutput didOutput")
        
        if self.delegate == nil || !(self.delegate?.responds(to: #selector(self.delegate?.easyCamDidCapture(image:))))! {
            self.semaphore.signal()
            return;
        }
        
        if (self.delegate?.responds(to: #selector(self.delegate?.easyCamDidCapture(sampleBuffer:))))! {
            self.delegateQueue.async {
                self.delegate?.easyCamDidCapture?(sampleBuffer: sampleBuffer)
            }
        }
        
        //Creates UIImage from buffer
        if let pixedBuffer = CMSampleBufferGetImageBuffer(sampleBuffer){
            let ciImage = CIImage.init(cvImageBuffer: pixedBuffer)
            let context = CIContext(options: nil)
            if let capturedImage = context.createCGImage(ciImage, from: CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(pixedBuffer), height: CVPixelBufferGetHeight(pixedBuffer))){
                let uiImage = UIImage(cgImage: capturedImage)
                self.delegateQueue.async {
                    self.delegate?.easyCamDidCapture?(image: uiImage)
                    self.semaphore.signal()
                }
            }
        }
    }
    
}

extension EasyCamViewController {
    
    internal func addObservers() {
        let keyValueObservation = session.observe(\.isRunning, options: .new) { _, change in
            guard let isSessionRunning = change.newValue else { return }
            
            // Only enable the ability to change camera if the device has more than one camera.
            self.hasMultipleCameras = isSessionRunning && EasyCamViewController.getCameraDevices().count > 1
            
        }
        
        keyValueObservations.append(keyValueObservation)
        
        NotificationCenter.default.addObserver(self, selector: #selector(subjectAreaDidChange), name: .AVCaptureDeviceSubjectAreaDidChange, object: videoDeviceInput.device)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionRuntimeError), name: .AVCaptureSessionRuntimeError, object: session)
        
        /*
         A session can only run when the app is full screen. It will be interrupted
         in a multi-app layout, introduced in iOS 9, see also the documentation of
         AVCaptureSessionInterruptionReason. Add observers to handle these session
         interruptions and show a preview is paused message. See the documentation
         of AVCaptureSessionWasInterruptedNotification for other interruption reasons.
         */
        NotificationCenter.default.addObserver(self, selector: #selector(sessionWasInterrupted), name: .AVCaptureSessionWasInterrupted, object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionInterruptionEnded), name: .AVCaptureSessionInterruptionEnded, object: session)
    }
    
    internal func removeObservers() {
        NotificationCenter.default.removeObserver(self)
        for kvObserver in keyValueObservations {
            kvObserver.invalidate()
        }
        keyValueObservations.removeAll()
    }
    
    @objc func sessionWasInterrupted(notification: NSNotification) {
        debugPrint("sessionWasInterrupted")
    }
    
    @objc func sessionInterruptionEnded(notification: NSNotification) {
        debugPrint("sessionInterruptionEnded")
    }
    
    @objc func subjectAreaDidChange(notification: NSNotification) {
        debugPrint("subjectAreaDidChange")
        let devicePoint = CGPoint(x: 0.5, y: 0.5)
        focus(with: AVCaptureDevice.FocusMode.continuousAutoFocus, exposureMode: AVCaptureDevice.ExposureMode.continuousAutoExposure, at: devicePoint, monitorSubjectAreaChange: false)
    }
    
    @objc func sessionRuntimeError(notification: NSNotification) {
        debugPrint("sessionRuntimeError");
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError else { return }
        
        print("Capture session runtime error: \(error)")
        
        /*
         Automatically try to restart the session running if media services were
         reset and the last start running succeeded. Otherwise, enable the user
         to try to resume the session running.
         */
        if error.code == .mediaServicesWereReset {
            sessionQueue.async {
                if self.sessionIsRunning {
                    self.session.startRunning()
                    self.sessionIsRunning = self.session.isRunning
                }
            }
        } else {
            self.mainQueue.async {
                self.delegate?.easyCamDidFail(error: error)
            }
        }
    }

}
extension EasyCamViewController {
    
    public override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator);
        var videoOrientation = self.frameView.previewView.videoPreviewLayer.connection?.videoOrientation;
        
        switch UIDevice.current.orientation {
        case .landscapeLeft:
            videoOrientation = AVCaptureVideoOrientation.landscapeRight;
        case .landscapeRight:
            videoOrientation = AVCaptureVideoOrientation.landscapeLeft;
        default:
            videoOrientation = AVCaptureVideoOrientation.portrait
        }
        
        self.mainQueue.async {
            self.frameView.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height);
            self.view.layoutIfNeeded()
            self.frameView.previewView.videoPreviewLayer.connection?.videoOrientation = videoOrientation!
        }
    }
    
    private func focus(with focusMode: AVCaptureDevice.FocusMode, exposureMode: AVCaptureDevice.ExposureMode, at devicePoint: CGPoint, monitorSubjectAreaChange: Bool) {
        sessionQueue.async {
            let device = self.videoDeviceInput.device
            do {
                try device.lockForConfiguration()
                
                /*
                 Setting (focus/exposure)PointOfInterest alone does not initiate a (focus/exposure) operation.
                 Call set(Focus/Exposure)Mode() to apply the new point of interest.
                 */
                if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(focusMode) {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = focusMode
                }
                
                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode) {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = exposureMode
                }
                
                device.isSubjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
                device.unlockForConfiguration()
            } catch {
                print("Could not lock device for configuration: \(error)")
            }
        }
    }
}


extension EasyCamViewController {
    
    class func device(with mediaType: AVMediaType, preferringPosition: AVCaptureDevice.Position) -> AVCaptureDevice? {
        
        let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [AVCaptureDevice.DeviceType.builtInWideAngleCamera], mediaType: mediaType, position: preferringPosition).devices;
        
        for device in devices where device.position == preferringPosition{
            return device
        }
        
        return nil;
    }
    
    class func getCameraDevices() -> [AVCaptureDevice] {
        return AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .builtInDuoCamera],                                                                                   mediaType: .video, position: .unspecified).devices;
    }
    
}


//MARK : EasyCamControlsDelegate protocol

extension EasyCamViewController : EasyCamControlsDelegate {
    
    public func back() {
        if self.navigationController != nil {
            self.navigationController?.popViewController(animated: true)
        } else {
            self.dismiss(animated: true, completion: nil)
        }
        
    }
    
    public func stop() {
        if self.sessionIsRunning {
            self.session.stopRunning()
            self.sessionIsRunning = self.session.isRunning
        }
    }
    
    public func resume() {
        if !self.sessionIsRunning {
            self.session.startRunning()
            self.sessionIsRunning = self.session.isRunning
        }
    }
    
    public func captureStillImage() {
        //TODO
    }
    
}

