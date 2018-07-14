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
    func easyCamDidFail(error : Error)
    @objc optional func easyCamDidCapture(image: UIImage);
    @objc optional func easyCamDidCapture(sampleBuffer: CMSampleBuffer);
    @objc optional func easyCamDidCaptureStill(image: UIImage);
}

public enum EasyCamError : Error {
    case runTimeError(String)
    case camSetupError(String)
}

public class EasyCamViewController: UIViewController {
    
    public weak var delegate : EasyCamDelegate?
    
    private let semaphore = DispatchSemaphore(value: 2);
    
    private let session = AVCaptureSession()
    
    private var sessionIsRunning = false;
    
    private let videoDeviceOutput = AVCaptureVideoDataOutput()
    
    private var videoDeviceInput : AVCaptureDeviceInput!
    
    private var frameView = Bundle(for: EasyCamViewController.self).loadNibNamed("EasyCamFrameView", owner: self, options: nil)?.first as! EasyCamFrameView
    
    private let sessionQueue = DispatchQueue(label: "session queue", qos: DispatchQoS.default, attributes: [], autoreleaseFrequency: DispatchQueue.AutoreleaseFrequency.inherit, target: nil)
    
    private let mainQueue = DispatchQueue.main;
    
    private enum SessionSetupResult {
        case success, notAuthorized, failed;
    }
    
    private var sessionSetup : SessionSetupResult = .failed;
    
    public convenience init(frameView : EasyCamFrameView) {
        self.init()
        self.frameView = frameView
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
                self.session.startRunning()
                self.sessionIsRunning = true
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
            }
        }
    }
    
    private func configureSession() {
        
        self.session.beginConfiguration()
        
        guard let device = EasyCamViewController.device(with: .video, preferringPosition: AVCaptureDevice.Position.back) else {
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
            DispatchQueue.global().async {
                self.delegate?.easyCamDidCapture?(sampleBuffer: sampleBuffer)
            }
        }
        
        //Creates UIImage from buffer
        if let pixedBuffer = CMSampleBufferGetImageBuffer(sampleBuffer){
            let ciImage = CIImage.init(cvImageBuffer: pixedBuffer)
            let context = CIContext(options: nil)
            if let capturedImage = context.createCGImage(ciImage, from: CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(pixedBuffer), height: CVPixelBufferGetHeight(pixedBuffer))){
                let uiImage = UIImage(cgImage: capturedImage)
                self.mainQueue.async {
                    self.delegate?.easyCamDidCapture?(image: uiImage)
                    self.semaphore.signal()
                }
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
            self.sessionIsRunning = false
        }
    }
    
    public func resume() {
        if !self.sessionIsRunning {
            self.session.startRunning()
            self.sessionIsRunning = true
        }
    }
    
    public func captureStillImage() {
        //TODO
    }
    
}

