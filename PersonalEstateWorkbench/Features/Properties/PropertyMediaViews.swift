import AVKit
import Photos
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct PropertyMediaSection: View {
    var property: Property
    @Environment(\.modelContext) private var context
    @State private var photoItem: PhotosPickerItem?
    @State private var videoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var viewer: MediaAsset?
    @State private var playerURL: URL?
    @State private var selectedVideos: Set<UUID> = []
    @State private var shareURLs: [URL] = []
    @State private var showShare = false
    @State private var compress = true
    @State private var busy = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if property.photos.isEmpty {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.accent.opacity(0.08))
                    .frame(height: 160)
                    .overlay {
                        VStack(spacing: 6) {
                            Image(systemName: "camera").font(.title2).foregroundStyle(Theme.accent)
                            Text("还没有照片").foregroundStyle(Theme.muted)
                        }
                    }
            } else {
                TabView {
                    ForEach(property.photos) { asset in
                        photo(asset)
                            .onTapGesture { viewer = asset }
                    }
                }
                .tabViewStyle(.page)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            HStack {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("拍照") { showCamera = true }
                }
                PhotosPicker(selection: $photoItem, matching: .images) { Text("相册照片") }
                PhotosPicker(selection: $videoItem, matching: .videos) { Text("相册视频") }
            }
            .buttonStyle(.bordered)
            if !property.photos.isEmpty {
                Text("照片顺序").font(.subheadline.weight(.semibold))
                ForEach(property.photos) { asset in
                    HStack {
                        thumb(asset)
                        Text(asset.caption.isEmpty ? "照片" : asset.caption)
                        Spacer()
                        Button("上移") { move(asset, by: -1) }
                        Button("下移") { move(asset, by: 1) }
                        Button("删除", role: .destructive) { remove(asset) }
                    }
                }
            }
            if !property.videos.isEmpty {
                Text("视频").font(.subheadline.weight(.semibold))
                Toggle("分享前压缩到 720p", isOn: $compress)
                ForEach(property.videos) { asset in
                    HStack {
                        thumb(asset)
                        VStack(alignment: .leading) {
                            Text(asset.originalFilename.isEmpty ? "视频" : asset.originalFilename).lineLimit(1)
                            Text(ByteCountFormatter.string(fromByteCount: Int64(asset.fileSize), countStyle: .file))
                                .font(.caption).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Button(selectedVideos.contains(asset.id) ? "已选" : "选择") {
                            if selectedVideos.contains(asset.id) { selectedVideos.remove(asset.id) } else { selectedVideos.insert(asset.id) }
                        }
                        Button("播放") { playerURL = MediaStore.fileURL(asset.relativePath) }
                        Button("删除", role: .destructive) { remove(asset) }
                    }
                }
                HStack {
                    Button("分享所选") { Task { await shareSelected(captioned: false) } }
                        .disabled(selectedVideos.isEmpty || busy)
                    Button("生成字幕素材") { Task { await shareSelected(captioned: true) } }
                        .disabled(selectedVideos.isEmpty || busy)
                }
                .buttonStyle(.bordered)
                Text("文件名会带上小区、报价、物业和车位。字幕素材保留原声和画面比例，最高 720p。")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            if busy { ProgressView("正在处理视频") }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                defer { photoItem = nil }
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    await addPhoto(image)
                }
            }
        }
        .onChange(of: videoItem) { _, item in
            guard let item else { return }
            Task {
                defer { videoItem = nil }
                if let movie = try? await item.loadTransferable(type: VideoFile.self) {
                    await addVideo(movie.url)
                } else {
                    errorMessage = "没有读到这个视频。"
                }
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker { image in Task { await addPhoto(image) } }
        }
        .sheet(item: $viewer) { asset in
            PhotoViewer(asset: asset)
        }
        .sheet(item: playerBinding) { box in
            NavigationStack {
                VideoPlayer(player: AVPlayer(url: box.url))
                    .navigationTitle("视频")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { playerURL = nil } } }
            }
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: shareURLs)
        }
        .errorAlert($errorMessage)
    }

    private var playerBinding: Binding<URLBox?> {
        Binding(get: { playerURL.map { URLBox(url: $0) } }, set: { playerURL = $0?.url })
    }

    private func photo(_ asset: MediaAsset) -> some View {
        Group {
            if let image = MediaImageLoader.image(relativePath: asset.relativePath) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color.gray.opacity(0.2)
            }
        }
    }

    @ViewBuilder
    private func thumb(_ asset: MediaAsset) -> some View {
        if let image = MediaImageLoader.thumbnail(for: asset) {
            Image(uiImage: image).resizable().scaledToFill().frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Image(systemName: asset.kind == .video ? "video" : "photo").frame(width: 48, height: 48)
        }
    }

    private func addPhoto(_ image: UIImage) async {
        do {
            let asset = try MediaStore.importPhoto(image)
            asset.sortOrder = (property.photos.map(\.sortOrder).max() ?? 0) + 1
            asset.property = property
            context.insert(asset)
            property.updatedAt = Date()
            try context.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addVideo(_ url: URL) async {
        do {
            let asset = try await MediaStore.importVideo(from: url)
            asset.sortOrder = (property.videos.map(\.sortOrder).max() ?? 0) + 1
            asset.property = property
            context.insert(asset)
            property.updatedAt = Date()
            try context.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func move(_ asset: MediaAsset, by offset: Int) {
        var photos = property.photos
        guard let index = photos.firstIndex(where: { $0.id == asset.id }) else { return }
        let target = index + offset
        guard photos.indices.contains(target) else { return }
        photos.swapAt(index, target)
        for (order, item) in photos.enumerated() { item.sortOrder = order }
        try? context.save()
    }

    private func remove(_ asset: MediaAsset) {
        MediaStore.deleteFiles(for: asset)
        context.delete(asset)
        try? context.save()
    }

    private func shareSelected(captioned: Bool) async {
        busy = true
        defer { busy = false }
        var urls: [URL] = []
        let chosen = property.videos.filter { selectedVideos.contains($0.id) }
        for asset in chosen {
            let source = MediaStore.fileURL(asset.relativePath)
            if captioned {
                do {
                    let material = try await PropertyVideoMaterialService.make(from: source, property: property)
                    let video = try await MediaStore.importVideo(from: material.videoURL, caption: "字幕素材")
                    video.property = property
                    video.sortOrder = (property.videos.map(\.sortOrder).max() ?? 0) + 1
                    context.insert(video)
                    if let cover = try? MediaStore.importPhoto(material.coverImage, caption: "字幕封面") {
                        cover.property = property
                        cover.sortOrder = (property.photos.map(\.sortOrder).max() ?? 0) + 1
                        context.insert(cover)
                    }
                    urls.append(material.videoURL)
                } catch {
                    errorMessage = error.localizedDescription
                }
            } else if compress {
                let output = FileManager.default.temporaryDirectory.appendingPathComponent(ShareContentBuilder.videoBaseName(for: property) + "-\(asset.id.uuidString.prefix(4)).mp4")
                do {
                    try await PropertyVideoMaterialService.exportCompressed(input: source, output: output)
                    urls.append(output)
                } catch {
                    urls.append(source)
                }
            } else {
                let output = FileManager.default.temporaryDirectory.appendingPathComponent(ShareContentBuilder.videoBaseName(for: property) + "." + (source.pathExtension.isEmpty ? "mp4" : source.pathExtension))
                try? FileManager.default.removeItem(at: output)
                try? FileManager.default.copyItem(at: source, to: output)
                urls.append(output)
            }
        }
        try? context.save()
        shareURLs = urls
        showShare = !urls.isEmpty
    }
}

struct URLBox: Identifiable {
    var id: String { url.absoluteString }
    var url: URL
}

struct VideoFile: Transferable {
    var url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { file in
            SentTransferredFile(file.url)
        } importing: { received in
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
            try FileManager.default.copyItem(at: received.file, to: dest)
            return VideoFile(url: dest)
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

struct PhotoViewer: View {
    var asset: MediaAsset
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Group {
                if let image = MediaImageLoader.image(relativePath: asset.relativePath) {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    Text("照片副本找不到了")
                }
            }
            .navigationTitle("照片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存到相册") { save() } }
            }
            .errorAlert($message)
        }
    }

    private func save() {
        guard let image = MediaImageLoader.image(relativePath: asset.relativePath) else { return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { message = "没有相册写入权限。" }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, _ in
                DispatchQueue.main.async { message = success ? "已保存到相册。原件仍在相册里，应用内只是副本。" : "没有保存成功。" }
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    var items: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
