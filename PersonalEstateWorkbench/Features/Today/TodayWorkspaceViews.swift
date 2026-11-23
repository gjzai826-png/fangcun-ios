import SwiftData
import SwiftUI
import UIKit

struct TodayWorkspaceView: View {
    @Environment(\.modelContext) private var context
    @Environment(WorkspaceController.self) private var workspace
    @Query(sort: \Property.updatedAt, order: .reverse) private var properties: [Property]
    @Query(sort: \TaskItem.dueAt) private var tasks: [TaskItem]
    @Query(sort: \Viewing.scheduledStart) private var viewings: [Viewing]
    @Query private var needs: [ClientNeed]
    @Query private var contacts: [Contact]
    @Query private var communities: [Community]
    @Query private var followUps: [FollowUp]

    @State private var day = Date()
    @State private var query = ""
    @State private var showDate = false
    @State private var dealPropertyID: UUID?
    @State private var followNeedID: UUID?
    @State private var showTask = false
    @State private var showDealPicker = false
    @State private var showNeedPicker = false
    @State private var path = NavigationPath()

    private var isToday: Bool { CNDate.sameDay(day, Date()) }
    private var dayViewings: [Viewing] {
        viewings.filter { $0.status == .scheduled && CNDate.sameDay($0.scheduledStart, day) }
    }
    private var dayTasks: [TaskItem] {
        tasks.filter { WorkflowService.appears(on: day, task: $0, includeOverdue: isToday) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                if BusinessRules.trimmed(query).isEmpty {
                    dashboard
                } else {
                    searchResults
                }
            }
            .paperScreen()
            .navigationTitle("今日")
            .navigationDestination(for: RecordRoute.self) { RouteDestination(route: $0) }
            .searchable(text: $query, prompt: "小区、别名、楼栋房号、联系人")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("其他日期") { showDate = true }
                }
            }
            .sheet(isPresented: $showDate) {
                NavigationStack {
                    DatePicker("查看日期", selection: $day, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .padding()
                        .navigationTitle("查看其他日期")
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showDate = false } } }
                }
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showDealPicker) { dealPicker }
            .sheet(isPresented: $showNeedPicker) { needPicker }
            .sheet(isPresented: $showTask) { NavigationStack { TaskFormView() } }
            .sheet(item: dealBinding) { box in NavigationStack { DealFormView(propertyID: box.id) } }
            .sheet(item: followBinding) { box in NavigationStack { FollowUpFormView(needID: box.id) } }
            .onAppear { refresh() }
        }
    }

    private var dashboard: some View {
        VStack(alignment: .leading, spacing: 16) {
            if workspace.mode == .demo {
                Text("当前是演示数据，和正式工作台分开存放。")
                    .font(.footnote)
                    .foregroundStyle(Theme.accent)
                    .card()
            }
            Text(CNDate.friendly(day))
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
            statRow
            quickActions
            SectionTitle(text: "当日带看")
            if dayViewings.isEmpty {
                EmptyStateView(title: "这一天没有带看", message: "安排带看后会出现在这里。完成和取消的不计入。", systemImage: "figure.walk")
            } else {
                ForEach(dayViewings) { viewing in
                    Button { path.append(RecordRoute.viewing(viewing.id)) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(CNDate.time(viewing.scheduledStart))–\(CNDate.time(viewing.scheduledEnd))")
                                .font(.headline)
                                .foregroundStyle(Theme.ink)
                            Text(viewing.clientNeed?.contact?.displayName ?? "未关联客户")
                                .foregroundStyle(Theme.muted)
                            Text(viewing.meetingPoint.isEmpty ? "见面地点未填" : viewing.meetingPoint)
                                .font(.subheadline)
                                .foregroundStyle(Theme.ink)
                        }
                        .card()
                    }
                }
            }
            SectionTitle(text: isToday ? "待办" : "当天待办")
            if dayTasks.isEmpty {
                EmptyStateView(title: "没有待办", message: "房源核实、租约到期、跟进和手动待办会汇总在这里。", systemImage: "checklist")
            } else {
                ForEach(dayTasks) { task in
                    taskRow(task)
                }
            }
            SectionTitle(text: "最近房源")
            ForEach(properties.filter { !$0.isArchived }.prefix(5)) { property in
                Button { path.append(RecordRoute.property(property.id)) } label: {
                    PropertyRow(property: property)
                }
            }
        }
        .padding()
    }

    private var statRow: some View {
        HStack(spacing: 8) {
            stat("在售", properties.filter { !$0.isArchived && $0.listingKind == .sale && $0.status == .available }.count)
            stat("在租", properties.filter { !$0.isArchived && $0.listingKind == .rent && $0.status == .available }.count)
            stat("待核实", properties.filter { !$0.isArchived && $0.status.needsReview }.count)
            stat("待办", dayTasks.count)
        }
    }

    private func stat(_ title: String, _ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(count)").font(.title2.weight(.semibold)).foregroundStyle(Theme.ink)
            Text(title).font(.caption).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var quickActions: some View {
        HStack(spacing: 8) {
            ForEach(TodayQuickAction.allCases) { action in
                Button {
                    switch action {
                    case .registerDeal: showDealPicker = true
                    case .writeFollowUp: showNeedPicker = true
                    case .addTask: showTask = true
                    }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: action.systemImage)
                        Text(action.title).font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
    }

    private func taskRow(_ task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Badge(text: task.kind.title, color: Theme.accent)
                if task.dueAt < Date() && !CNDate.sameDay(task.dueAt, day) {
                    Badge(text: "逾期", color: Theme.bad)
                }
                Spacer()
            }
            Text(task.title).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
            if !task.notes.isEmpty {
                Text(task.notes).font(.subheadline).foregroundStyle(Theme.muted)
            }
            HStack {
                if task.kind != .verification {
                    Button("完成") { WorkflowService.setState(task, state: .completed); try? context.save(); refresh() }
                    Button("取消") { WorkflowService.setState(task, state: .cancelled); try? context.save(); refresh() }
                }
                if let sourceID = task.sourceID {
                    Button("去处理") { open(task.kind, sourceID) }
                }
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.bordered)
        }
        .card()
    }

    private func open(_ kind: TaskKind, _ id: UUID) {
        switch kind {
        case .verification: path.append(RecordRoute.property(id))
        case .lease: path.append(RecordRoute.deal(id))
        case .viewing: path.append(RecordRoute.viewing(id))
        case .followUp:
            if let follow = followUps.first(where: { $0.id == id }) {
                if let needID = follow.clientNeed?.id { path.append(RecordRoute.need(needID)); return }
                if let propertyID = follow.property?.id { path.append(RecordRoute.property(propertyID)); return }
                if let contactID = follow.contact?.id { path.append(RecordRoute.contact(contactID)); return }
            }
        case .manual: break
        }
    }

    private var searchResults: some View {
        let hits = GlobalSearch.hits(query: query, communities: communities, properties: properties, contacts: contacts)
        return VStack(alignment: .leading, spacing: 10) {
            if hits.isEmpty {
                EmptyStateView(title: "没有找到", message: "已归档的不会计入。电话可按数字查找联系人。", systemImage: "magnifyingglass")
            }
            ForEach(hits) { hit in
                Button { path.append(hit.route) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(hit.title).foregroundStyle(Theme.ink)
                        Text(hit.subtitle).font(.subheadline).foregroundStyle(Theme.muted)
                    }
                    .card()
                }
            }
        }
        .padding()
    }

    private var dealPicker: some View {
        NavigationStack {
            List(properties.filter(\.canRegisterDeal)) { property in
                Button("\(property.communityName) \(property.doorText)") { 
                    showDealPicker = false
                    dealPropertyID = property.id
                }
            }
            .navigationTitle("选择可登记房源")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { showDealPicker = false } } }
        }
    }

    private var needPicker: some View {
        NavigationStack {
            List(needs.filter { $0.status == .active }) { need in
                Button("\(need.contact?.displayName ?? "客户") · \(need.kind.title)") {
                    showNeedPicker = false
                    followNeedID = need.id
                }
            }
            .navigationTitle("选择进行中的需求")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { showNeedPicker = false } } }
        }
    }

    private var dealBinding: Binding<UUIDBox?> {
        Binding(get: { dealPropertyID.map(UUIDBox.init) }, set: { dealPropertyID = $0?.id })
    }

    private var followBinding: Binding<UUIDBox?> {
        Binding(get: { followNeedID.map(UUIDBox.init) }, set: { followNeedID = $0?.id })
    }

    private func refresh() {
        try? WorkflowService.sync(context: context)
        let currentTasks = (try? context.all(TaskItem.self)) ?? []
        let currentDeals = (try? context.all(Deal.self)) ?? []
        Task { await LocalNotificationService.reschedule(tasks: currentTasks, deals: currentDeals) }
    }
}

struct UUIDBox: Identifiable {
    var id: UUID
}

struct SearchHit: Identifiable {
    var id: String
    var title: String
    var subtitle: String
    var route: RecordRoute
}

enum GlobalSearch {
    static func hits(query: String, communities: [Community], properties: [Property], contacts: [Contact]) -> [SearchHit] {
        let text = BusinessRules.trimmed(query)
        let digits = BusinessRules.digits(text)
        var hits: [SearchHit] = []
        for community in communities where !community.isArchived {
            let names = ([community.name, community.district, community.address] + community.aliases).joined(separator: " ")
            if names.localizedCaseInsensitiveContains(text) {
                hits.append(SearchHit(id: "c-\(community.id)", title: community.name, subtitle: community.district, route: .community(community.id)))
            }
        }
        for property in properties where !property.isArchived {
            let door = "\(property.building) \(property.unit) \(property.room) \(property.communityName) \(property.community?.aliases.joined() ?? "")"
            if door.localizedCaseInsensitiveContains(text) {
                hits.append(SearchHit(id: "p-\(property.id)", title: "\(property.communityName) \(property.doorText)", subtitle: property.statusTitle, route: .property(property.id)))
            }
        }
        for contact in contacts where !contact.isArchived {
            let nameHit = contact.displayName.localizedCaseInsensitiveContains(text) || contact.wechat.localizedCaseInsensitiveContains(text)
            let phoneHit = digits.count >= 3 && BusinessRules.digits(contact.phone).contains(digits)
            if nameHit || phoneHit {
                hits.append(SearchHit(id: "u-\(contact.id)", title: contact.displayName, subtitle: contact.roleTitle, route: .contact(contact.id)))
            }
        }
        return hits
    }
}

struct PropertyRow: View {
    var property: Property

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 4) {
                Text("\(property.communityName) \(property.doorText)")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text("\(property.layoutText) · \(property.areaText)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                HStack {
                    Text(Money.priceText(property.askingPriceCents, kind: property.listingKind))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    Badge(text: property.statusTitle, color: statusColor(property.status))
                }
                TagWrap(tags: property.features.filter { FeatureToken.feeTokens.contains($0) || FeatureToken.parkingTokens.contains($0) })
            }
            Spacer(minLength: 0)
        }
        .card()
    }

    private var thumbnail: some View {
        Group {
            if let photo = property.photos.first, let image = MediaImageLoader.thumbnail(for: photo) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.accent.opacity(0.08))
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
