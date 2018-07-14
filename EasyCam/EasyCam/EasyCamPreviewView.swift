//
//  EasyCamPreviewView.swift
//  EasyCam
//
//  Created by Rodrigo Morbach on 12/07/18.
//  Copyright © 2018 Morbach Inc. All rights reserved.
//

import UIKit
import AVFoundation

public class EasyCamPreviewView: UIView {

    var videoPreviewLayer : AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }
    
    var session : AVCaptureSession? {
        get {
            return videoPreviewLayer.session
        }
        set {
            videoPreviewLayer.session = newValue
        }
    }
    
    override public class var layerClass : AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
}
