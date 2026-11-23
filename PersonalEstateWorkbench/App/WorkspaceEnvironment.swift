import Foundation
import SwiftData

@MainActor
@Observable
final class WorkspaceController {
    private(set) var container: ModelContainer?
    private(set) var mode: WorkspaceMode = .formal
    var loadError: String?
    var pendingImportURL: URL?

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.modeKey) ?? ""
        load(WorkspaceMode(rawValue: saved) ?? .formal)
    }

    func load(_ mode: WorkspaceMode) {
        do {
            let store = try Self.storeURL(mode)
            let media = store.deletingLastPathComponent().appendingPathComponent("Media-\(mode.rawValue)", isDirectory: true)
            MediaStore.prepare(root: media)
            let configuration = ModelConfiguration(
                mode.rawValue,
                schema: EstateSchema.schema,
                url: store,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(for: EstateSchema.schema, configurations: [configuration])
            if mode == .demo {
                DemoDataSeeder.seedIfNeeded(container.mainContext)
            } else {
                DemoDataSeeder.ensureWorkspace(container.mainContext, title: "正式工作台")
            }
            self.container = container
            self.mode = mode
            self.loadError = nil
            UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey)
        } catch {
            container = nil
            loadError = error.localizedDescription
        }
    }

    func resetDemo() {
        guard let store = try? Self.storeURL(.demo) else { return }
        Self.destroy(store)
        let media = store.deletingLastPathComponent().appendingPathComponent("Media-demo", isDirectory: true)
        try? FileManager.default.removeItem(at: media)
        load(.demo)
    }

    func recover(from backup: URL) {
        do {
            let store = try Self.storeURL(.formal)
            if FileManager.default.fileExists(atPath: store.path) {
                let broken = store.deletingLastPathComponent().appendingPathComponent("formal-broken-\(UUID().uuidString).store")
                try FileManager.default.moveItem(at: store, to: broken)
                for suffix in ["-wal", "-shm"] {
                    let sidecar = URL(fileURLWithPath: store.path + suffix)
                    if FileManager.default.fileExists(atPath: sidecar.path) {
                        try? FileManager.default.moveItem(at: sidecar, to: URL(fileURLWithPath: broken.path + suffix))
                    }
                }
            }
            load(.formal)
            guard let context = container?.mainContext else {
                loadError = "新的工作台没有建立起来。"
                return
            }
            try DataPortabilityService.restore(from: backup, context: context)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private static let modeKey = "workspace.mode"

    private static func storeURL(_ mode: WorkspaceMode) throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Workspaces", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("\(mode.rawValue).store")
    }

    private static func destroy(_ url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }
}
