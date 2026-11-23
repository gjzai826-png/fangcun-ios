import SwiftData
import SwiftUI

enum RecordRoute: Hashable {
    case property(UUID)
    case need(UUID)
    case contact(UUID)
    case community(UUID)
    case deal(UUID)
    case viewing(UUID)
    case comparable(UUID)
    case communities
    case contacts
    case deals
    case market
    case data
    case notifications
    case about
    case cloud
    case matchNeed(UUID)
    case matchProperty(UUID)
}

struct RootView: View {
    @Environment(WorkspaceController.self) private var workspace

    var body: some View {
        Group {
            if let container = workspace.container {
                MainTabView()
                    .modelContainer(container)
                    .id(workspace.mode)
            } else {
                RecoveryView()
            }
        }
        .onOpenURL { url in
            workspace.pendingImportURL = url
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            TodayWorkspaceView()
                .tabItem { Label("今日", systemImage: "sun.max.fill") }
            PropertyListView()
                .tabItem { Label("房源", systemImage: "house.fill") }
            ClientNeedListView()
                .tabItem { Label("客户", systemImage: "person.2.fill") }
            MineView()
                .tabItem { Label("我的", systemImage: "square.grid.2x2.fill") }
        }
    }
}

struct RouteDestination: View {
    var route: RecordRoute

    var body: some View {
        switch route {
        case .property(let id): PropertyDetailView(propertyID: id)
        case .need(let id): ClientNeedDetailView(needID: id)
        case .contact(let id): ContactDetailView(contactID: id)
        case .community(let id): CommunityDetailView(communityID: id)
        case .deal(let id): DealDetailView(dealID: id)
        case .viewing(let id): ViewingDetailView(viewingID: id)
        case .comparable(let id): MarketDetailView(comparableID: id)
        case .communities: CommunityListView()
        case .contacts: ContactListView()
        case .deals: DealListView()
        case .market: MarketListView()
        case .data: DataManagementView()
        case .notifications: NotificationSettingsView()
        case .about: AboutView()
        case .cloud: CloudDisabledView()
        case .matchNeed(let id): MatchPropertiesView(needID: id)
        case .matchProperty(let id): MatchNeedsView(propertyID: id)
        }
    }
}

struct RecoveryView: View {
    @Environment(WorkspaceController.self) private var workspace
    @State private var backups: [URL] = []

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                EmptyStateView(
                    title: "无法打开工作台",
                    message: workspace.loadError ?? "可以从恢复前的安全备份还原到一个新数据集。原来的库会留在本机。",
                    systemImage: "externaldrive.badge.exclamationmark"
                )
                ForEach(backups, id: \.path) { url in
                    Button(url.lastPathComponent) {
                        workspace.recover(from: url)
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button("再试一次正式工作台") { workspace.load(.formal) }
                Spacer()
            }
            .padding()
            .paperScreen()
            .navigationTitle("恢复")
            .onAppear { backups = DataPortabilityService.safetyBackups() }
        }
    }
}
