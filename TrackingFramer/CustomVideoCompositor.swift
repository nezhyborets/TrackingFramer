//
//  CustomVideoCompositor.swift
//  TrackingFramer
//
//  Created by Nezhyborets Oleksii on 8/24/20.
//  Copyright © 2020 nezhyborets. All rights reserved.
//

import AVFoundation
import Vision
import CoreImage

class CustomVideoCompositor: NSObject, AVVideoCompositing {
    private var objectInFrame: VNDetectedObjectObservation?
    private var sequenceRequestHandler: VNSequenceRequestHandler?
    private var debugEnabled: Bool {
        return false
    }

    var sourcePixelBufferAttributes: [String : Any]? {
        get {
            return ["\(kCVPixelBufferPixelFormatTypeKey)": kCVPixelFormatType_32BGRA]
        }
    }

    var requiredPixelBufferAttributesForRenderContext: [String : Any] {
        get {
            return ["\(kCVPixelBufferPixelFormatTypeKey)": kCVPixelFormatType_32BGRA]
        }
    }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
    }

    func startRequest(_ asyncVideoCompositionRequest: AVAsynchronousVideoCompositionRequest) {
        let sourcePixelBuffer = asyncVideoCompositionRequest.sourceFrame(byTrackID: asyncVideoCompositionRequest.sourceTrackIDs[0].int32Value)!


        let newPixelBuffer = asyncVideoCompositionRequest.renderContext.newPixelBuffer()
        var image = CIImage(cvPixelBuffer: sourcePixelBuffer)

        if let object = trackOrDetect(in: sourcePixelBuffer) {
            CVPixelBufferLockBaseAddress(sourcePixelBuffer, CVPixelBufferLockFlags.readOnly)
            defer {
                CVPixelBufferUnlockBaseAddress(sourcePixelBuffer, CVPixelBufferLockFlags.readOnly)
            }

            let width = CVPixelBufferGetWidth(sourcePixelBuffer)
            let height = CVPixelBufferGetHeight(sourcePixelBuffer)

            if debugEnabled {
                // Draw black rect
                let newContext = CGContext(
                    data: CVPixelBufferGetBaseAddress(sourcePixelBuffer),
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: CVPixelBufferGetBytesPerRow(sourcePixelBuffer),
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
                let objectRect = VNImageRectForNormalizedRect(object.boundingBox, width, height)
                newContext?.addRect(objectRect)
                newContext?.fillPath()
                asyncVideoCompositionRequest.finish(withComposedVideoFrame: sourcePixelBuffer)
                return
            } else {
                let transform = getTransform(
                    outputFrameSize: .init(width: width, height: height),
                    imageRectInitial: image.extent,
                    objectRectNormalized: object.boundingBox
                )

                image = image.transformed(by: transform)
            }
        }

        let context = CIContext()
        context.render(image, to: newPixelBuffer!)
        asyncVideoCompositionRequest.finish(withComposedVideoFrame: newPixelBuffer!)
    }

    private func getTransform(outputFrameSize: CGSize, imageRectInitial: CGRect, objectRectNormalized: CGRect) -> CGAffineTransform {
        var objectRect = VNImageRectForNormalizedRect(objectRectNormalized, Int(imageRectInitial.width), Int(imageRectInitial.height))
        var imageRect = imageRectInitial
        var offset = self.offset(ofObject: objectRect, fromCenterInFrameWithSize: outputFrameSize)
        var finalTransform = CGAffineTransform.identity

        while abs(offset.x) >= 1 && abs(offset.y) >= 1 {
            // Translate to fix object offset
            let translate = CGAffineTransform(translationX: -offset.x, y: -offset.y)
            imageRect = imageRect.applying(translate)
            finalTransform = finalTransform.concatenating(translate)

            // Scale in attemp to fill gaps after translate
            let scaleValue: CGFloat
            if abs(offset.y) > abs(offset.x) {
                let halfImage = (CGFloat(imageRect.height) / 2)
                scaleValue = (halfImage + abs(offset.y)) / halfImage
            } else {
                let halfImage = (CGFloat(imageRect.width) / 2)
                scaleValue = (halfImage + abs(offset.x)) / halfImage
            }

            let scale = CGAffineTransform(scaleX: scaleValue, y: scaleValue)
            imageRect = imageRect.applying(scale)
            finalTransform = finalTransform.concatenating(scale)

            // Translate to make previous scale aka center anchored
            var translationX: CGFloat = 0
            var translationY: CGFloat = 0

            if imageRect.origin.x > 0 {
                translationX = -imageRect.origin.x
            } else if imageRect.maxX < outputFrameSize.width {
                translationX = outputFrameSize.width - imageRect.maxX
            }

            if imageRect.origin.y > 0 {
                translationY = -imageRect.origin.y
            } else if imageRect.maxY < outputFrameSize.height {
                translationY = outputFrameSize.height - imageRect.maxY
            }

            if translationX > 0 || translationY > 0 {
                let translate2 = CGAffineTransform(translationX: translationX, y: translationY)
                imageRect = imageRect.applying(translate2)
                finalTransform = finalTransform.concatenating(translate2)
            }

            // Find object rect again, by calculating it's position...
            objectRect = VNImageRectForNormalizedRect(objectRectNormalized, Int(imageRect.width), Int(imageRect.height))
            // ... and converting it to output frame coordinate system
            objectRect = objectRect.offsetBy(dx: imageRect.origin.x, dy: imageRect.origin.y)

            offset = self.offset(ofObject: objectRect, fromCenterInFrameWithSize: outputFrameSize)
        }

        return finalTransform
    }

    private func print(_ string: String) {
        Swift.print(string)
    }

    private func offset(ofObject objectRect: CGRect, fromCenterInFrameWithSize frameSize: CGSize) -> CGPoint {
        let frameCenter = CGPoint(x: frameSize.width / 2, y: frameSize.height / 2)
        let objectCenter = CGPoint(x: objectRect.midX, y: objectRect.midY)
        return .init(x: objectCenter.x - frameCenter.x, y: objectCenter.y - frameCenter.y)
    }

    private func trackOrDetect(in pixelBuffer: CVPixelBuffer) -> VNDetectedObjectObservation? {
        if let object = objectInFrame {
            objectInFrame = track(object: object, pixelBuffer: pixelBuffer)
        } else {
            objectInFrame = detect(in: pixelBuffer)
        }

        return objectInFrame
    }

    private func detect(in pixelBuffer: CVPixelBuffer) -> VNDetectedObjectObservation? {
        let request = VNDetectHumanRectanglesRequest { (request, error) in
        }

        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try! requestHandler.perform([request])

        let observationWithBiggestBoundingBox = request.results?.max(by: { (first, second) -> Bool in
            let size1 = (first as! VNDetectedObjectObservation).boundingBox.size
            let size2 = (second as! VNDetectedObjectObservation).boundingBox.size
            return size1.width * size1.height < size2.width * size2.height
        })

        guard let firstObjectObservation = observationWithBiggestBoundingBox as? VNDetectedObjectObservation else {
            return nil
        }

        return firstObjectObservation
    }

    private func track(object: VNDetectedObjectObservation, pixelBuffer: CVPixelBuffer) -> VNDetectedObjectObservation? {
        let sequenceRequestHandler: VNSequenceRequestHandler = self.sequenceRequestHandler ?? VNSequenceRequestHandler()
        if self.sequenceRequestHandler == nil {
            self.sequenceRequestHandler = sequenceRequestHandler
        }

        let request = VNTrackObjectRequest(detectedObjectObservation: object) { (request, error) in
        }
        request.trackingLevel = .accurate

        try! sequenceRequestHandler.perform([request], on: pixelBuffer)

        guard let firstObjectObservation = request.results?.first as? VNDetectedObjectObservation else {
            return nil
        }

        return firstObjectObservation
    }
}
