import SwiftData
import SwiftUI

struct CommunityListView: View {
    @Query(sort: \Community.name) private var communities: [Community]
    @State private var query = ""
    @State private var showArchived = false
    @State private var editing: Community?
    @State private var creating = false
    @State private var stars = StarStore.starredCommunityIDs

    private var visible: [Community] {
        communities.filter { community in
            (showArchived || !community.isArchived) &&
            (query.isEmpty || community.name.localizedCaseInsensitiveContains(query)
                || community.aliasText.localizedCaseInsensitiveContains(query)
                || community.district.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        List {
            if !stars.isEmpty {
                Section("常用") {
                    ForEach(communities.filter { stars.contains($0.id) }) { community in
                        NavigationLink(value: RecordRoute.community(community.id)) { row(community) }
                    }
                }
            }
            Section("全部") {
                ForEach(visible) { community in
                    NavigationLink(value: RecordRoute.community(community.id)) { row(community) }
                }
            }
        }
        .navigationTitle("小区字典")
        .searchable(text: $query, prompt: "名称、别名或区域")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Toggle("已归档", isOn: $showArchived).font(.caption) }
            ToolbarItem(placement: .topBarTrailing) { Button("新建") { creating = true } }
        }
        .sheet(isPresented: $creating) { NavigationStack { CommunityFormView() } }
    }

    private func row(_ community: Community) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(community.name)
                if community.isArchived { Badge(text: "已归档", color: Theme.muted) }
            }
            Text([community.district, community.address].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
    }
}

struct CommunityDetailView: View {
    var communityID: UUID
    @Query private var communities: [Community]
    @Environment(\.modelContext) private var context
    @State private var editing = false
    private var community: Community? { communities.first { $0.id == communityID } }

    var body: some View {
        Group {
            if let community {
                List {
                    Section {
                        InfoRow(title: "别名", value: community.aliasText)
                        InfoRow(title: "区域", value: community.district)
                        InfoRow(title: "地址", value: community.address)
                        if community.latitude != nil || community.longitude != nil {
                            InfoRow(title: "坐标", value: "\(community.latitude ?? 0), \(community.longitude ?? 0)")
                        }
                        if !community.notes.isEmpty { Text(community.notes) }
                    }
                    Section("房源") {
                        ForEach(community.properties) { property in
                            NavigationLink(value: RecordRoute.property(property.id)) {
                                Text("\(property.doorText) · \(property.statusTitle)")
                            }
                        }
                    }
                    Section {
                        Button(StarStore.isStarred(community.id) ? "取消常用" : "标为常用") {
                            StarStore.toggleStar(community.id)
                        }
                        Button(community.isArchived ? "取消归档" : "归档") {
                            community.isArchived.toggle()
                            community.updatedAt = Date()
                            try? context.save()
                        }
                    } footer: {
                        Text("可能重名时请结合区域和地址区分，系统不会自动合并。归档不会删除已关联房源。")
                    }
                }
                .navigationTitle(community.name)
                .toolbar { Button("编辑") { editing = true } }
                .sheet(isPresented: $editing) { NavigationStack { CommunityFormView(existingID: community.id) } }
            } else {
                EmptyStateView(title: "没有这个小区", message: "", systemImage: "building.2")
            }
        }
    }
}

struct CommunityFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var communities: [Community]
    var existingID: UUID?
    var suggestedName: String = ""
    var onSaved: (UUID) -> Void = { _ in }

    @State private var name = ""
    @State private var aliases = ""
    @State private var district = ""
    @State private var address = ""
    @State private var notes = ""
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var isDirty = false
    @State private var didLoad = false
    @State private var errorMessage: String?
    @State private var warning: String?

    var body: some View {
        Form {
            TextField("全名", text: $name)
            TextField("别名，顿号分隔", text: $aliases)
            TextField("区域", text: $district)
            TextField("地址", text: $address)
            TextField("备注", text: $notes, axis: .vertical)
            TextField("纬度", text: $latitude).keyboardType(.decimalPad)
            TextField("经度", text: $longitude).keyboardType(.decimalPad)
        }
        .navigationTitle(existingID == nil ? "新建小区" : "编辑小区")
        .navigationBarTitleDisplayMode(.inline)
        .formExitProtection(isDirty: isDirty)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("保存") { save(force: false) } } }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            if let existing = communities.first(where: { $0.id == existingID }) {
                name = existing.name
                aliases = existing.aliasText
                district = existing.district
                address = existing.address
                notes = existing.notes
                latitude = existing.latitude.map(String.init) ?? ""
                longitude = existing.longitude.map(String.init) ?? ""
            } else {
                name = suggestedName
            }
        }
        .onChange(of: name) { _, _ in isDirty = true }
        .errorAlert($errorMessage)
        .alert("可能重名", isPresented: Binding(get: { warning != nil }, set: { if !$0 { warning = nil } })) {
            Button("仍然保存") { save(force: true) }
            Button("返回修改", role: .cancel) {}
        } message: { Text(warning ?? "") }
    }

    private func save(force: Bool) {
        if let message = BusinessRules.validateCommunity(name: name) {
            errorMessage = message
            return
        }
        let trimmed = BusinessRules.trimmed(name)
        let others = communities.filter { $0.id != existingID && $0.name == trimmed }.count
        if !force, let message = BusinessRules.duplicateCommunityWarning(name: trimmed, others: others) {
            warning = message
            return
        }
        let community = communities.first { $0.id == existingID } ?? Community(name: trimmed)
        if existingID == nil { context.insert(community) }
        community.name = trimmed
        community.aliases = BusinessRules.splitList(aliases)
        community.district = BusinessRules.trimmed(district)
        community.address = BusinessRules.trimmed(address)
        community.notes = BusinessRules.trimmed(notes)
        community.latitude = Double(latitude)
        community.longitude = Double(longitude)
        community.updatedAt = Date()
        try? context.save()
        isDirty = false
        onSaved(community.id)
        dismiss()
    }
}
