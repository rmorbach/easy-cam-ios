//
//  ViewController.swift
//  EasyCamApp
//
//  Created by Rodrigo Morbach on 12/07/18.
//  Copyright © 2018 Morbach Inc. All rights reserved.
//

import UIKit
import EasyCam
import AVFoundation

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(true)
        initCameraWithDefaultConfiguration()
    }
    
    func initCameraWithDefaultConfiguration() {
        
        let captureSettings = EasyCamCaptureSettings(cameraPosition: AVCaptureDevice.Position.back, sessionPreset: AVCaptureSession.Preset.iFrame1280x720, videoGravity: EasyCamCaptureSettings.VideoGravity.resizeAspectFill);
        
        let cam = EasyCamViewController(captureSettings: captureSettings)
        cam.delegate = self;
        self.navigationController?.pushViewController(cam, animated: true)
    }
    
    func initCameraWithCustomView() {
        if let frameView = Bundle.main.loadNibNamed("CamFrameView", owner: self, options: nil)?.first as? EasyCamFrameView {
            let cam = EasyCamViewController(frameView: frameView, captureSettings: nil)
            cam.delegate = self;
            self.navigationController?.pushViewController(cam, animated: true)
        }
    }

}

extension ViewController : EasyCamDelegate {
    
    func easyCamDidCapture(image: UIImage) {
        
    }
    func easyCamDidFail(error: Error) {
        
    }
    
}
