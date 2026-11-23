import SwiftUI

struct MineView: View {
    @Environment(WorkspaceController.self) private var workspace
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("方寸").font(.title2.weight(.semibold))
                        Text(workspace.mode.title).foregroundStyle(Theme.muted)
                    }
                    .padding(.vertical, 4)
                }
                Section("资料") {
                    NavigationLink("小区字典", value: RecordRoute.communities)
                    NavigationLink("联系人", value: RecordRoute.contacts)
                    NavigationLink("个人成交", value: RecordRoute.deals)
                    NavigationLink("行情", value: RecordRoute.market)
                }
                Section("数据") {
                    NavigationLink("备份、恢复与 CSV", value: RecordRoute.data)
                    NavigationLink("提醒设置", value: RecordRoute.notifications)
                }
                Section {
                    NavigationLink(value: RecordRoute.cloud) {
                        HStack {
                            Text("方寸云端同步")
                            Spacer()
                            Text("未启用").foregroundStyle(Theme.muted)
                        }
                    }
                } footer: {
                    Text("本机使用，不连接云端。")
                }
                Section {
                    NavigationLink("关于", value: RecordRoute.about)
                }
            }
            .navigationTitle("我的")
            .navigationDestination(for: RecordRoute.self) { RouteDestination(route: $0) }
        }
    }
}
