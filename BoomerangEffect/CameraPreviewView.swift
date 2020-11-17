//
//  CameraPreviewView.swift
//  BoomerangEffect
//
//  Created by Govardhan Goli on 11/10/20.
//

import UIKit
import AVFoundation

class CameraPreviewView: UIView {
    //overriding the views default layer to be a video preview layer instead of a vanilla CAlayer
    
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
    /// Convenience wrapper to get layer as its statically known type.
    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }
    
}
