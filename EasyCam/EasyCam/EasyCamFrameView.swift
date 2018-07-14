//
//  EasyCamFrameView.swift
//  EasyCam
//
//  Created by Rodrigo Morbach on 14/07/18.
//  Copyright © 2018 Morbach Inc. All rights reserved.
//

import UIKit

@objc public protocol EasyCamControlsDelegate : NSObjectProtocol {
    @objc func back()
    @objc func stop()
    @objc func resume()
    @objc optional func captureStillImage()
}

open class EasyCamFrameView: UIView {

    @IBOutlet weak var previewView: EasyCamPreviewView!
    public weak var  easyCamControlDelegate : EasyCamControlsDelegate?
 
    
    //MARK: IBAction methods
    
    
    @IBAction func resume(_ sender: UIBarButtonItem) {
    
        if (self.easyCamControlDelegate?.responds(to: #selector(self.easyCamControlDelegate?.resume)))! {
            self.easyCamControlDelegate?.resume()
        }
        
    }
    
    @IBAction func stop(_ sender: UIBarButtonItem) {
        self.easyCamControlDelegate?.stop()
    }
    
}
