//
//  ViewController.swift
//  TrackingFramer
//
//  Created by Nezhyborets Oleksii on 8/24/20.
//  Copyright © 2020 nezhyborets. All rights reserved.
//

import UIKit
import AVKit

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        let playerViewController = AVPlayerViewController()
        playerViewController.player = AVPlayer(playerItem: playerItem())
        present(playerViewController, animated: true, completion: nil)
    }

    private func playerItem() -> AVPlayerItem {
        let url = Bundle.main.url(forResource: "vetal", withExtension: "m4v")!
        let asset = AVAsset(url: url)

        let composition = AVMutableComposition()
        let videoAssetTrack = asset.tracks(withMediaType: .video).first!

        let videoCompositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        try! videoCompositionTrack.insertTimeRange(
            .init(start: .zero, duration: videoAssetTrack.timeRange.duration),
            of: videoAssetTrack,
            at: .zero
        )

        let renderSize = CGSize(width: 1080, height: 1920)
        let playerItem = AVPlayerItem(asset: composition)
        playerItem.videoComposition = videoComposition(
            renderSize: renderSize,
            sourceTrack: videoAssetTrack,
            compositionTrack: videoCompositionTrack
        )
        return playerItem
    }

    private func videoComposition(renderSize: CGSize, sourceTrack: AVAssetTrack, compositionTrack: AVMutableCompositionTrack) -> AVVideoComposition {
        let videoComposition = AVMutableVideoComposition()
        let videoCompositionInstruction = AVMutableVideoCompositionInstruction()
        videoCompositionInstruction.timeRange = .init(start: .zero, duration: sourceTrack.timeRange.duration)

        let layerInstruction = videoCompositionLayerInstruction(
            videoCompositionTrack: compositionTrack,
            assetTrack: sourceTrack,
            renderSize: renderSize
        )

        videoCompositionInstruction.layerInstructions = [layerInstruction]

        videoComposition.instructions = [videoCompositionInstruction]
        videoComposition.customVideoCompositorClass = CustomVideoCompositor.self
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = sourceTrack.minFrameDuration
        return videoComposition
    }

    private func customVideoCompositor() -> AVVideoCompositing {
        return CustomVideoCompositor()
    }

    private func videoCompositionLayerInstruction(
        videoCompositionTrack: AVMutableCompositionTrack,
        assetTrack: AVAssetTrack,
        renderSize: CGSize
    ) -> AVMutableVideoCompositionLayerInstruction {
        let instruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoCompositionTrack)
//        instruction.setTransform(
//            compositionTransform(renderSize: renderSize, sourceAssetTrack: assetTrack),
//            at: CMTime.zero
//        )
        return instruction
    }

    private func compositionTransform(renderSize: CGSize, sourceAssetTrack: AVAssetTrack) -> CGAffineTransform {
        let assetSize = naturalSize(of: sourceAssetTrack)
        let scaleToFillRatio = max(renderSize.width / assetSize.width, renderSize.height / assetSize.height)
        let scaleFactor = CGAffineTransform(scaleX: scaleToFillRatio, y: scaleToFillRatio)

        let translationY = renderSize.height / 2 - (assetSize.height * scaleToFillRatio / 2)
        let translationX = renderSize.width / 2 - (assetSize.width * scaleToFillRatio / 2)

        let preferredTransform = sourceAssetTrack.preferredTransform
        var concat = preferredTransform
            .concatenating(scaleFactor)
            .concatenating(CGAffineTransform(translationX: translationX, y: translationY))

        if is90DegreeLeftRotation(preferredTransform) && preferredTransform.tx == 0 {
            concat = concat.concatenating(.init(translationX: renderSize.width, y: 0))
        }

        if is90DegreeRightRotation(preferredTransform) && preferredTransform.ty == 0 {
            concat = concat.concatenating(.init(translationX: 0, y: renderSize.height))
        }

        if isMirrored(preferredTransform) && preferredTransform.tx == 0 && preferredTransform.ty == 0 {
            let scaledSize = CGSize(width: assetSize.width * scaleToFillRatio, height: assetSize.height * scaleToFillRatio)

            concat = concat.concatenating(
                .init(translationX: scaledSize.width, y: scaledSize.height)
            )
        }

        return concat
    }

    // x' = x * -1
    // y' = y * -1
    private func isMirrored(_ transform: CGAffineTransform) -> Bool {
        transform.a == -1 && transform.b == 0 && transform.c == 0 && transform.d == -1
    }

    // x' = y
    // y' = x
    private func isFlipAndRightRotation(_ transform: CGAffineTransform) -> Bool {
        transform.a == 0 && transform.b == 1 && transform.c == 1 && transform.d == 0
    }

    private func naturalSize(of assetTrack: AVAssetTrack) -> CGSize {
        let shouldSwap = transformIncludes90DegreeRotation(assetTrack.preferredTransform)
        guard shouldSwap else {
            return assetTrack.naturalSize
        }

        return CGSize(width: assetTrack.naturalSize.height, height: assetTrack.naturalSize.width)
    }

    private func transformIncludes90DegreeRotation(_ transform: CGAffineTransform) -> Bool {
        return isFlipAndRightRotation(transform)
            || is90DegreeLeftRotation(transform)
            || is90DegreeRightRotation(transform)
    }

    // x' = -y
    // y' = x
    private func is90DegreeLeftRotation(_ transform: CGAffineTransform) -> Bool {
        transform.a == 0 && transform.b == 1 && transform.c == -1 && transform.d == 0
    }

    // x' = y
    // y' = -x
    private func is90DegreeRightRotation(_ transform: CGAffineTransform) -> Bool {
        transform.a == 0 && transform.b == -1 && transform.c == 1 && transform.d == 0
    }
}
