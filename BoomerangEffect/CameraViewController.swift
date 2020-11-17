//
//  CameraViewController.swift
//  BoomerangEffect
//
//  Created by Govardhan Goli on 11/10/20.
//

import UIKit
import AVFoundation
import Photos

class CameraViewController: UIViewController, AVCaptureFileOutputRecordingDelegate {
    @IBOutlet weak var cameraPreviewView: CameraPreviewView!
    @IBOutlet weak var recordButton: UIButton!
    
    var captureSesion: AVCaptureSession!
    var recordOutput: AVCaptureMovieFileOutput!
    var videoUrl = URL(string: "") // use your own url
    var frames = [UIImage]()
    private var generator:AVAssetImageGenerator!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        setupCaptureSession()
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(true)
        captureSesion.startRunning()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(true)
        captureSesion.stopRunning()
    }
    
    
    //the recording gets output on a background queue
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        DispatchQueue.main.async {
            self.updateViews()
        }
    }

    func getAllFrames(videourl: URL) {
       let asset:AVAsset = AVAsset(url:videourl)
       let duration:Float64 = CMTimeGetSeconds(asset.duration)
       self.generator = AVAssetImageGenerator(asset:asset)
        self.generator.requestedTimeToleranceBefore = CMTime.zero
        self.generator.requestedTimeToleranceAfter = CMTime.zero
       self.generator.appliesPreferredTrackTransform = true
       self.frames = []
        let sequence = stride(from: 0, to: duration, by: 0.5)
        for element in sequence {
            self.getFrame(fromTime:element)
        }
       self.generator = nil
    }

    private func getFrame(fromTime:Float64) {
        let time:CMTime = CMTimeMakeWithSeconds(fromTime, preferredTimescale:600)
        let image:CGImage
        do {
           try image = self.generator.copyCGImage(at:time, actualTime:nil)
        } catch {
           return
        }
        self.frames.append(UIImage(cgImage:image))
    }
    
    func saveVideoToLibrary(videoURL: URL) {

        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
        }) { saved, error in

            if let error = error {
                print("Error saving video to librayr: \(error.localizedDescription)")
            }
            if saved {
                print("Video save to library")

            }
        }
    }
    
  private  func buildVideoFromImageArray(framesArray:[UIImage]) {
        var images = framesArray
        let outputSize = CGSize(width:images[0].size.width, height: images[0].size.height)
        let fileManager = FileManager.default
        let urls = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        guard let documentDirectory = urls.first else {
            fatalError("documentDir Error")
        }

        let videoOutputURL = documentDirectory.appendingPathComponent("OutputVideo.mp4")

        if FileManager.default.fileExists(atPath: videoOutputURL.path) {
            do {
                try FileManager.default.removeItem(atPath: videoOutputURL.path)
            } catch {
                fatalError("Unable to delete file: \(error) : \(#function).")
            }
        }

        guard let videoWriter = try? AVAssetWriter(outputURL: videoOutputURL, fileType: AVFileType.mp4) else {
            fatalError("AVAssetWriter error")
        }

        let outputSettings = [AVVideoCodecKey : AVVideoCodecType.h264, AVVideoWidthKey : NSNumber(value: Float(outputSize.width)), AVVideoHeightKey : NSNumber(value: Float(outputSize.height))] as [String : Any]

        guard videoWriter.canApply(outputSettings: outputSettings, forMediaType: AVMediaType.video) else {
            fatalError("Negative : Can't apply the Output settings...")
        }

        let videoWriterInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: outputSettings)
        let sourcePixelBufferAttributesDictionary = [
            kCVPixelBufferPixelFormatTypeKey as String : NSNumber(value: kCVPixelFormatType_32ARGB),
            kCVPixelBufferWidthKey as String: NSNumber(value: Float(outputSize.width)),
            kCVPixelBufferHeightKey as String: NSNumber(value: Float(outputSize.height))
        ]
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoWriterInput, sourcePixelBufferAttributes: sourcePixelBufferAttributesDictionary)

        if videoWriter.canAdd(videoWriterInput) {
            videoWriter.add(videoWriterInput)
        }

        if videoWriter.startWriting() {
            videoWriter.startSession(atSourceTime: CMTime.zero)
            assert(pixelBufferAdaptor.pixelBufferPool != nil)

            let media_queue = DispatchQueue(__label: "mediaInputQueue", attr: nil)

            videoWriterInput.requestMediaDataWhenReady(on: media_queue, using: { () -> Void in
                let fps: Int32 = 8//2
                let frameDuration = CMTimeMake(value: 1, timescale: fps)

                var frameCount: Int64 = 0
                var appendSucceeded = true

                while (!images.isEmpty) {
                    if (videoWriterInput.isReadyForMoreMediaData) {
                        let nextPhoto = images.remove(at: 0)
                        let lastFrameTime = CMTimeMake(value: frameCount, timescale: fps)
                        let presentationTime = frameCount == 0 ? lastFrameTime : CMTimeAdd(lastFrameTime, frameDuration)

                        var pixelBuffer: CVPixelBuffer? = nil
                        let status: CVReturn = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferAdaptor.pixelBufferPool!, &pixelBuffer)

                        if let pixelBuffer = pixelBuffer, status == 0 {
                            let managedPixelBuffer = pixelBuffer

                            CVPixelBufferLockBaseAddress(managedPixelBuffer, [])

                            let data = CVPixelBufferGetBaseAddress(managedPixelBuffer)
                            let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
                            let context = CGContext(data: data, width: Int(outputSize.width), height: Int(outputSize.height), bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(managedPixelBuffer), space: rgbColorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)

                            context?.clear(CGRect(x: 0, y: 0, width: outputSize.width, height: outputSize.height))

                            let horizontalRatio = CGFloat(outputSize.width) / nextPhoto.size.width
                            let verticalRatio = CGFloat(outputSize.height) / nextPhoto.size.height

                            let aspectRatio = min(horizontalRatio, verticalRatio) // ScaleAspectFit

                            let newSize = CGSize(width: nextPhoto.size.width * aspectRatio, height: nextPhoto.size.height * aspectRatio)

                            let x = newSize.width < outputSize.width ? (outputSize.width - newSize.width) / 2 : 0
                            let y = newSize.height < outputSize.height ? (outputSize.height - newSize.height) / 2 : 0

                            context?.draw(nextPhoto.cgImage!, in: CGRect(x: x, y: y, width: newSize.width, height: newSize.height))

                            CVPixelBufferUnlockBaseAddress(managedPixelBuffer, [])

                            appendSucceeded = pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime)
                        } else {
                            print("Failed to allocate pixel buffer")
                            appendSucceeded = false
                        }
                    }
                    if !appendSucceeded {
                        break
                    }
                    frameCount += 1
                }
                videoWriterInput.markAsFinished()
                videoWriter.finishWriting { () -> Void in
                    print("Done saving")
                    // Save video to the library
                    self.saveVideoToLibrary(videoURL: videoOutputURL)
                }
            })
        }
    }
    
  
    
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        
        DispatchQueue.main.async {
            
            
            self.getAllFrames(videourl: outputFileURL)
            var reversearr = [UIImage]()
            reversearr  = self.frames.reversed()
            if reversearr.count>0{
                reversearr.remove(at: 0)
            }
           self.frames.append(contentsOf: reversearr)
            self.buildVideoFromImageArray(framesArray: self.frames)
            defer {self.updateViews()}
        }
    }
    
   // Setup hte camera session
    func setupCaptureSession() {
        //make the capture session
        let captureSession = AVCaptureSession()
        //configure the inputs
        let cameraDevice = bestCamera()
        
        guard let audioDevice = AVCaptureDevice.default(for: .audio) else {return}
        
        guard let cameraDeviceInput = try? AVCaptureDeviceInput(device: cameraDevice), /* guard */ captureSession.canAddInput(cameraDeviceInput) else {
            fatalError("Unable to create camera input")
        }
        
        guard let audioDeviceInput = try? AVCaptureDeviceInput(device: audioDevice) else {return}
        
        //"take this camera and use it to record video when the session begins"
        captureSession.addInput(cameraDeviceInput)
        captureSession.addInput(audioDeviceInput)
        
        //configure outputs
        let fileOutput = AVCaptureMovieFileOutput()
        
        guard captureSession.canAddOutput(fileOutput) else {
            fatalError("Unable to add movie file output to capture session")
        }
        
        captureSession.addOutput(fileOutput)
        
        
        //configure the session
        
        captureSession.sessionPreset = .hd1920x1080
        //ready to begin running everything
        captureSession.commitConfiguration()//lock in the inputs, outputs, session presets, etc
      
        self.captureSesion = captureSession
        self.recordOutput = fileOutput
        
        //gives the video information frames to the preview view to be shown to the user
        cameraPreviewView.videoPreviewLayer.session = captureSession
        
    }
     //* AVCaptureDevice.default(.builtInMicrophone, for: .audio, position: .front)*
    
    
    
    private func bestCamera() -> AVCaptureDevice {
        //the users device has a dual camera
        if let device = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) {
            return device
        } else  if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            //single camera on users device
            return device
            
        } else {
            fatalError("Missing expected back camera on device")
        }
        
    }
    
    private func updateViews() {
    
        let isRecording = recordOutput.isRecording
        
        let recordButtonImage = isRecording ? "Stop" : "Record"
        recordButton.setImage(UIImage(named: recordButtonImage), for: .normal)
        
    }
    
    private func newRecordingURL() -> URL {
        
        let documentDir = try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        
        return documentDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
    }
    
    
    @IBAction func recordButtonPressed(_ sender: UIButton) {
        
        if recordOutput.isRecording {
           recordOutput.stopRecording()
        } else {
            recordOutput.startRecording(to: newRecordingURL(), recordingDelegate: self)
        }
        
    }
    
}

