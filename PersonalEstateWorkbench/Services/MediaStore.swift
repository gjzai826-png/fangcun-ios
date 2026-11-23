import AVFoundation
import UIKit

enum MediaStoreError: LocalizedError {
    case unreadable
    case fileTooLarge
    case totalTooLarge

    var errorDescription: String? {
        switch self {
        case .unreadable: return "没有读到这个照片或视频。"
        case .fileTooLarge: return "单个文件不能超过 100 MB。"
        case .totalTooLarge: return "媒体合计不能超过 16 GB。"
        }
    }
}

enum MediaStore {
    static var root: URL = FileManager.default.temporaryDirectory

    static func prepare(root: URL) {
        self.root = root
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    static func fileURL(_ relativePath: String) -> URL {
        root.appendingPathComponent(relativePath)
    }

    static func totalBytes() -> Int64 {
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        return files.reduce(Int64(0)) { sum, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return sum + Int64(size)
        }
    }

    static func importPhoto(_ image: UIImage, caption: String = "") throws -> MediaAsset {
        guard let full = jpeg(image, maxSide: 2560, quality: 0.86),
              let thumb = jpeg(image, maxSide: 480, quality: 0.8) else {
            throw MediaStoreError.unreadable
        }
        try ensureCapacity(adding: full.count + thumb.count)
        let id = UUID()
        let name = "\(id.uuidString).jpg"
        let thumbName = "\(id.uuidString)-thumb.jpg"
        try full.write(to: fileURL(name), options: .atomic)
        try thumb.write(to: fileURL(thumbName), options: .atomic)
        return MediaAsset(
            id: id,
            kind: .photo,
            relativePath: name,
            thumbnailRelativePath: thumbName,
            originalFilename: name,
            mimeType: "image/jpeg",
            fileSize: full.count,
            caption: caption
        )
    }

    static func importVideo(from url: URL, caption: String = "") async throws -> MediaAsset {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if size > BusinessRules.maxMediaFileBytes { throw MediaStoreError.fileTooLarge }
        try ensureCapacity(adding: size)
        let id = UUID()
        let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
        let name = "\(id.uuidString).\(ext)"
        try FileManager.default.copyItem(at: url, to: fileURL(name))
        var thumbName = ""
        if let thumb = await videoThumbnail(fileURL(name)), let data = jpeg(thumb, maxSide: 480, quality: 0.8) {
            thumbName = "\(id.uuidString)-thumb.jpg"
            try? data.write(to: fileURL(thumbName), options: .atomic)
        }
        return MediaAsset(
            id: id,
            kind: .video,
            relativePath: name,
            thumbnailRelativePath: thumbName,
            originalFilename: url.lastPathComponent,
            mimeType: "video/mp4",
            fileSize: size,
            caption: caption
        )
    }

    static func deleteFiles(for asset: MediaAsset) {
        if !asset.relativePath.isEmpty {
            try? FileManager.default.removeItem(at: fileURL(asset.relativePath))
        }
        if !asset.thumbnailRelativePath.isEmpty {
            try? FileManager.default.removeItem(at: fileURL(asset.thumbnailRelativePath))
        }
    }

    static func replaceRoot(with staging: URL) throws {
        let parent = root.deletingLastPathComponent()
        let retired = parent.appendingPathComponent("MediaRetired-\(UUID().uuidString)")
        if FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.moveItem(at: root, to: retired)
        }
        try FileManager.default.moveItem(at: staging, to: root)
        try? FileManager.default.removeItem(at: retired)
    }

    static func removeOrphans(referenced: Set<String>) -> Int {
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return 0
        }
        var removed = 0
        for file in files where !referenced.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
            removed += 1
        }
        return removed
    }

    private static func ensureCapacity(adding bytes: Int) throws {
        if bytes > BusinessRules.maxMediaFileBytes { throw MediaStoreError.fileTooLarge }
        if totalBytes() + Int64(bytes) > BusinessRules.maxMediaTotalBytes { throw MediaStoreError.totalTooLarge }
    }

    static func jpeg(_ image: UIImage, maxSide: CGFloat, quality: CGFloat) -> Data? {
        redraw(image, maxSide: maxSide).jpegData(compressionQuality: quality)
    }

    static func redraw(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        var size = image.size
        let longest = max(size.width, size.height)
        if longest > maxSide, longest > 0 {
            let scale = maxSide / longest
            size = CGSize(width: size.width * scale, height: size.height * scale)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private static func videoThumbnail(_ url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        do {
            let (image, _) = try await generator.image(at: .zero)
            return UIImage(cgImage: image)
        } catch {
            return nil
        }
    }
}

enum MediaImageLoader {
    static func image(relativePath: String) -> UIImage? {
        guard !relativePath.isEmpty else { return nil }
        return UIImage(contentsOfFile: MediaStore.fileURL(relativePath).path)
    }

    static func thumbnail(for asset: MediaAsset) -> UIImage? {
        if let image = image(relativePath: asset.thumbnailRelativePath) { return image }
        if asset.kind == .photo { return image(relativePath: asset.relativePath) }
        return nil
    }
}
