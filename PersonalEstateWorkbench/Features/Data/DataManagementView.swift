import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct DataManagementView: View {
    @Environment(\.modelContext) private var context
    @Environment(WorkspaceController.self) private var workspace
    @State private var exportDocument: EstateBackupDocument?
    @State private var showExport = false
    @State private var showImport = false
    @State private var pendingImport: URL?
    @State private var csvDocument: CSVDocument?
    @State private var showCSV = false
    @State private var csvName = "方寸.csv"
    @State private var message: String?
    @State private var errorMessage: String?
    @State private var backups: [URL] = []

    var body: some View {
        List {
            Section {
                Button("导出完整备份") { exportBackup() }
                Button("从备份恢复") { showImport = true }
            } footer: {
                Text("完整备份是未加密的 .estatebackup 包，含业务记录和本机照片视频。恢复前会先做当前工作台的安全备份，然后整库替换，不会自动合并。请自行保管文件。")
            }
            Section("CSV 分类型导出") {
                ForEach(CSVExportKind.allCases) { kind in
                    Button(kind.title) { exportCSV(kind) }
                }
            } footer: {
                Text("CSV 不能用来完整恢复。金额列同时有人民币分和显示金额。")
            }
            Section("恢复前安全备份") {
                if backups.isEmpty {
                    Text("还没有安全备份。")
                }
                ForEach(backups, id: \.path) { url in
                    Button(url.lastPathComponent) { pendingImport = url }
                }
            } footer: {
                Text("只保留最近 3 份，避免占满空间。无法打开工作台时，可以从这里还原到新数据集，原库会留在本机。")
            }
            Section {
                Button("清理未引用的媒体文件") { cleanOrphans() }
                LabeledContent("媒体占用", value: ByteCountFormatter.string(fromByteCount: MediaStore.totalBytes(), countStyle: .file))
            }
            Section {
                Button(workspace.mode == .demo ? "返回正式工作台" : "使用演示数据") {
                    if workspace.mode == .demo { workspace.load(.formal) } else { workspace.load(.demo) }
                }
                if workspace.mode == .demo {
                    Button("重置演示数据", role: .destructive) { workspace.resetDemo() }
                }
            } footer: {
                Text("演示数据单独存放，覆盖租房、买房、跟进、带看、成交和行情。不会改正式工作台。")
            }
        }
        .navigationTitle("数据")
        .onAppear { backups = DataPortabilityService.safetyBackups() }
        .fileExporter(isPresented: $showExport, document: exportDocument, contentType: .estateBackup, defaultFilename: exportDocument?.packageURL.lastPathComponent ?? "方寸备份.estatebackup") { result in
            if case .failure(let error) = result { errorMessage = error.localizedDescription }
        }
        .fileExporter(isPresented: $showCSV, document: csvDocument, contentType: .commaSeparatedText, defaultFilename: csvName) { result in
            if case .failure(let error) = result { errorMessage = error.localizedDescription }
        }
        .fileImporter(isPresented: $showImport, allowedContentTypes: [.estateBackup]) { result in
            if case .success(let url) = result { pendingImport = url }
            if case .failure(let error) = result { errorMessage = error.localizedDescription }
        }
        .confirmationDialog("用这份备份替换当前工作台？", isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }), titleVisibility: .visible) {
            Button("先备份当前数据，再整库替换", role: .destructive) {
                guard let url = pendingImport else { return }
                pendingImport = nil
                restore(url)
            }
            Button("取消", role: .cancel) { pendingImport = nil }
        } message: {
            Text("不会自动合并。文件未加密。")
        }
        .alert("完成", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("好") {}
        } message: { Text(message ?? "") }
        .errorAlert($errorMessage)
        .onChange(of: workspace.pendingImportURL) { _, url in
            pendingImport = url
            workspace.pendingImportURL = nil
        }
    }

    private func exportBackup() {
        do {
            let url = try DataPortabilityService.exportPackage(context: context)
            exportDocument = EstateBackupDocument(packageURL: url)
            showExport = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exportCSV(_ kind: CSVExportKind) {
        do {
            csvDocument = CSVDocument(text: try DataPortabilityService.csv(kind, context: context))
            csvName = kind.filename
            showCSV = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restore(_ url: URL) {
        do {
            try DataPortabilityService.restore(from: url, context: context)
            backups = DataPortabilityService.safetyBackups()
            message = "已替换为备份里的数据。"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cleanOrphans() {
        let assets = (try? context.all(MediaAsset.self)) ?? []
        var names = Set(assets.map(\.relativePath) + assets.map(\.thumbnailRelativePath))
        names.remove("")
        let removed = MediaStore.removeOrphans(referenced: names)
        message = removed == 0 ? "没有未引用的文件。" : "清理了 \(removed) 个未引用文件。"
    }
}

struct NotificationSettingsView: View {
    @Environment(\.modelContext) private var context
    @State private var enabled = NotificationPreferences.isEnabled
    @State private var status = "尚未询问"

    var body: some View {
        Form {
            Toggle("本地提醒", isOn: $enabled)
            LabeledContent("系统权限", value: status)
            Text("租约提前 30 天和到期当日 09:00 提醒。通知只写简短事项，不含电话、门牌或内部备注。关掉系统通知后，应用里的待办仍会保留。")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
        }
        .navigationTitle("提醒设置")
        .onAppear { Task { await refreshStatus() } }
        .onChange(of: enabled) { _, newValue in
            Task { await toggle(newValue) }
        }
    }

    private func toggle(_ on: Bool) async {
        if on {
            let granted = await LocalNotificationService.requestAuthorization()
            NotificationPreferences.isEnabled = granted
            enabled = granted
        } else {
            NotificationPreferences.isEnabled = false
        }
        let tasks = (try? context.all(TaskItem.self)) ?? []
        let deals = (try? context.all(Deal.self)) ?? []
        await LocalNotificationService.reschedule(tasks: tasks, deals: deals)
        await refreshStatus()
    }

    private func refreshStatus() async {
        switch await LocalNotificationService.authorizationStatus() {
        case .authorized, .provisional, .ephemeral: status = "已允许"
        case .denied: status = "已关闭"
        case .notDetermined: status = "尚未询问"
        @unknown default: status = "未知"
        }
    }
}

struct CloudDisabledView: View {
    var body: some View {
        List {
            Section {
                LabeledContent("方寸云端同步", value: "未启用")
            } footer: {
                Text("正式云同步尚未启用。本版本是个人单机，不登录、不连接云端。换机请用完整备份。")
            }
        }
        .navigationTitle("云同步")
    }
}

struct AboutView: View {
    var body: some View {
        List {
            LabeledContent("名称", value: "方寸")
            LabeledContent("版本", value: "0.1.0 (10)")
            LabeledContent("用途", value: "个人房产工作台")
            Text("数据只在这台手机上。备份文件没有加密。")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
        }
        .navigationTitle("关于")
    }
}
