import AVFoundation
import UIKit

struct VideoMaterial: Identifiable {
    var id = UUID()
    var videoURL: URL
    var coverImage: UIImage
    var caption: String
}

enum PropertyVideoMaterialService {
    static func make(from source: URL, property: Property) async throws -> VideoMaterial {
        let caption = [
            property.communityName,
            Money.priceText(property.askingPriceCents, kind: property.listingKind),
            property.layoutText
        ].filter { !$0.isEmpty && $0 != "户型未填" && $0 != "未报价" }.joined(separator: "  ")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("video-material-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let output = folder.appendingPathComponent(ShareContentBuilder.videoBaseName(for: property) + "-字幕.mp4")
        do {
            try await exportCaptioned(input: source, output: output, caption: caption)
        } catch {
            try await exportCompressed(input: source, output: output)
        }
        let cover = await coverImage(from: output, title: property.communityName, subtitle: caption)
        return VideoMaterial(videoURL: output, coverImage: cover, caption: caption)
    }

    static func exportCompressed(input: URL, output: URL) async throws {
        let asset = AVURLAsset(url: input)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else {
            throw MediaStoreError.unreadable
        }
        session.outputURL = output
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        await session.export()
        if session.status != .completed {
            throw session.error ?? MediaStoreError.unreadable
        }
    }

    private static func exportCaptioned(input: URL, output: URL, caption: String) async throws {
        let asset = AVURLAsset(url: input)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let sourceVideo = videoTracks.first else { throw MediaStoreError.unreadable }
        let duration = try await asset.load(.duration)
        let natural = try await sourceVideo.load(.naturalSize)
        let preferred = try await sourceVideo.load(.preferredTransform)
        let composition = AVMutableComposition()
        guard let compVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw MediaStoreError.unreadable
        }
        let range = CMTimeRange(start: .zero, duration: duration)
        try compVideo.insertTimeRange(range, of: sourceVideo, at: .zero)
        if let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first,
           let compAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try compAudio.insertTimeRange(range, of: sourceAudio, at: .zero)
        }

        let transformed = CGRect(origin: .zero, size: natural).applying(preferred)
        let oriented = CGSize(width: abs(transformed.width), height: abs(transformed.height))
        let render = fitted(oriented)
        let scale = oriented.width > 0 ? render.width / oriented.width : 1
        var transform = preferred
        transform = transform.concatenating(CGAffineTransform(translationX: -transformed.minX, y: -transformed.minY))
        transform = transform.concatenating(CGAffineTransform(scaleX: scale, y: scale))

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = range
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideo)
        layerInstruction.setTransform(transform, at: .zero)
        instruction.layerInstructions = [layerInstruction]

        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: render)
        let parent = CALayer()
        parent.frame = CGRect(origin: .zero, size: render)
        parent.isGeometryFlipped = true
        let text = CATextLayer()
        text.string = caption
        text.fontSize = max(22, render.width / 28)
        text.alignmentMode = .center
        text.foregroundColor = UIColor.white.cgColor
        text.backgroundColor = UIColor.black.withAlphaComponent(0.45).cgColor
        text.isWrapped = true
        text.contentsScale = 2
        let barHeight = max(64, render.height * 0.12)
        text.frame = CGRect(x: 0, y: 20, width: render.width, height: barHeight)
        parent.addSublayer(videoLayer)
        parent.addSublayer(text)

        let videoComposition = AVMutableVideoComposition()
        videoComposition.instructions = [instruction]
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.renderSize = render
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parent)

        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw MediaStoreError.unreadable
        }
        session.outputURL = output
        session.outputFileType = .mp4
        session.videoComposition = videoComposition
        session.shouldOptimizeForNetworkUse = true
        await session.export()
        if session.status != .completed {
            throw session.error ?? MediaStoreError.unreadable
        }
    }

    static func coverImage(from video: URL, title: String, subtitle: String) async -> UIImage {
        let asset = AVURLAsset(url: video)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)
        let base: UIImage
        if let (cg, _) = try? await generator.image(at: CMTime(seconds: 0.4, preferredTimescale: 600)) {
            base = UIImage(cgImage: cg)
        } else {
            base = UIImage()
        }
        let size = base.size == .zero ? CGSize(width: 1280, height: 720) : base.size
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor(red: 0.25, green: 0.22, blue: 0.55, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            base.draw(in: CGRect(origin: .zero, size: size))
            let bar = CGRect(x: 0, y: size.height * 0.72, width: size.width, height: size.height * 0.28)
            UIColor.black.withAlphaComponent(0.45).setFill()
            context.fill(bar)
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: size.width / 16),
                .foregroundColor: UIColor.white
            ]
            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: size.width / 24),
                .foregroundColor: UIColor.white
            ]
            (title as NSString).draw(in: CGRect(x: 24, y: bar.minY + 16, width: size.width - 48, height: 60), withAttributes: titleAttrs)
            (subtitle as NSString).draw(in: CGRect(x: 24, y: bar.minY + 72, width: size.width - 48, height: 80), withAttributes: subAttrs)
        }
    }

    private static func fitted(_ size: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return CGSize(width: 1280, height: 720) }
        let longSide = max(size.width, size.height)
        let shortSide = min(size.width, size.height)
        let scale = min(1, min(1280 / longSide, 720 / shortSide))
        var width = (size.width * scale).rounded(.down)
        var height = (size.height * scale).rounded(.down)
        width = width - width.truncatingRemainder(dividingBy: 2)
        height = height - height.truncatingRemainder(dividingBy: 2)
        return CGSize(width: max(2, width), height: max(2, height))
    }
}
