# easy-cam-ios
A Cocoa Touch framework to facilitate the camera usage in iOS

# Usage

* Import the binary to your projeto
```
import EasyCam
```
* Create a instance of EasyCamViewController using default configuration
```
let cam = EasyCamViewController()
cam.delegate = self;
```
* or provide a custom implementation of `EasyCamFrameView`
```
if let frameView = Bundle.main.loadNibNamed("CamFrameView", owner: self, options: nil)?.first as? EasyCamFrameView {
    let cam = EasyCamViewController(frameView: frameView, captureSettings: nil)
    cam.delegate = self;            
}
```

* you can also provide your own settings for capture, such as preferred camera. In this case, you must also import `AVFoundation` module:
```
import AVFoundation
import EasyCam

let captureSettings = EasyCamCaptureSettings(cameraPosition: AVCaptureDevice.Position.back, sessionPreset: AVCaptureSession.Preset.iFrame1280x720, videoGravity: EasyCamCaptureSettings.VideoGravity.resizeAspectFill);
let cam = EasyCamViewController(captureSettings: captureSettings)
cam.delegate = self;

```
* Implement `EasyCamDelegate` protocol;


# Notes
Obviously EasyCam needs access to the camera. Starting from iOS 10, apps that don’t provide a usage description for this permission would be rejected when submitted to the App Store.

Add the follow key to your app’s info.plist file with text explaining to the user why those permissions are needed:
```NSCameraUsageDescription```
Add a value to this key with a description of the goal of camera usage, for example: 

"<app name> needs access to the camera to be able to recognize objects."

# TODOs

* Allow to change camera in runtime.
* Implement photo capture.
* Implement movie capture.
* Add support for live mode.
* Improve convenience init more camera configurations.

# Acknowledgment

Most of the code is based on Apple's sample code available [here](https://developer.apple.com/library/archive/samplecode/AVCam/Introduction/Intro.html)