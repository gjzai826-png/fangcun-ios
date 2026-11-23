import SwiftData
import SwiftUI

struct FollowUpFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var needs: [ClientNeed]
    @Query private var properties: [Property]
    @Query private var contacts: [Contact]

    var propertyID: UUID?
    var needID: UUID?
    var contactID: UUID?

    @State private var channel: FollowUpChannel = .call
    @State private var content = ""
    @State private var outcome = ""
    @State private var nextAction = ""
    @State private var hasNext = false
    @State private var nextDate = Date()
    @State private var occurred = Date()
    @State private var selectedNeed: UUID?
    @State private var selectedProperty: UUID?
    @State private var selectedContact: UUID?
    @State private var isDirty = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Picker("渠道", selection: $channel) { ForEach(FollowUpChannel.allCases) { Text($0.title).tag($0) } }
            TextField("内容", text: $content, axis: .vertical)
            TextField("结果", text: $outcome)
            TextField("下一步", text: $nextAction)
            Toggle("下次联系", isOn: $hasNext)
            if hasNext { DatePicker("时间", selection: $nextDate) }
            DatePicker("发生时间", selection: $occurred)
            Picker("需求", selection: $selectedNeed) {
                Text("不关联").tag(UUID?.none)
                ForEach(needs) { need in Text(need.contact?.displayName ?? need.kind.title).tag(Optional(need.id)) }
            }
            Picker("房源", selection: $selectedProperty) {
                Text("不关联").tag(UUID?.none)
                ForEach(properties) { property in Text("\(property.communityName) \(property.doorText)").tag(Optional(property.id)) }
            }
            Picker("联系人", selection: $selectedContact) {
                Text("不关联").tag(UUID?.none)
                ForEach(contacts) { contact in Text(contact.displayName).tag(Optional(contact.id)) }
            }
        }
        .navigationTitle("写跟进")
        .navigationBarTitleDisplayMode(.inline)
        .formExitProtection(isDirty: isDirty)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("保存") { save() } } }
        .onAppear {
            selectedNeed = needID
            selectedProperty = propertyID
            selectedContact = contactID ?? needs.first { $0.id == needID }?.contact?.id
        }
        .onChange(of: content) { _, _ in isDirty = true }
        .errorAlert($errorMessage)
    }

    private func save() {
        let need = needs.first { $0.id == selectedNeed }
        let property = properties.first { $0.id == selectedProperty }
        let contact = contacts.first { $0.id == selectedContact }
        let matches = need == nil || contact == nil || need?.contact?.id == contact?.id
        if let message = BusinessRules.validateFollowUp(
            hasNeed: need != nil, hasProperty: property != nil, hasContact: contact != nil, contactMatchesNeed: matches
        ) {
            errorMessage = message
            return
        }
        let follow = FollowUp(
            channel: channel,
            content: BusinessRules.trimmed(content),
            outcome: outcome,
            nextAction: nextAction,
            nextDueAt: hasNext ? nextDate : nil,
            occurredAt: occurred
        )
        follow.clientNeed = need
        follow.property = property
        follow.contact = contact ?? need?.contact
        context.insert(follow)
        try? context.save()
        try? WorkflowService.sync(context: context)
        isDirty = false
        dismiss()
    }
}

struct TaskFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var title = ""
    @State private var notes = ""
    @State private var due = Date()
    @State private var isDirty = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            TextField("事项", text: $title)
            TextField("备注", text: $notes, axis: .vertical)
            DatePicker("时间", selection: $due)
        }
        .navigationTitle("添加待办")
        .navigationBarTitleDisplayMode(.inline)
        .formExitProtection(isDirty: isDirty)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("保存") { save() } } }
        .onChange(of: title) { _, _ in isDirty = true }
        .errorAlert($errorMessage)
    }

    private func save() {
        let trimmed = BusinessRules.trimmed(title)
        guard !trimmed.isEmpty else { errorMessage = "先写事项。"; return }
        let task = TaskItem(kind: .manual, title: trimmed, notes: notes, dueAt: due, sourceKey: "manual:\(UUID().uuidString)")
        context.insert(task)
        try? context.save()
        isDirty = false
        dismiss()
    }
}

struct ViewingFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var needs: [ClientNeed]
    @Query private var properties: [Property]
    @Query private var viewings: [Viewing]
    var existingID: UUID?
    var needID: UUID?

    @State private var selectedNeed: UUID?
    @State private var start = Date()
    @State private var end = Date().addingTimeInterval(3600)
    @State private var meeting = ""
    @State private var notes = ""
    @State private var selected: Set<UUID> = []
    @State private var isDirty = false
    @State private var didLoad = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Picker("需求", selection: $selectedNeed) {
                Text("请选择").tag(UUID?.none)
                ForEach(needs) { need in
                    Text("\(need.contact?.displayName ?? "客户") · \(need.kind.title)").tag(Optional(need.id))
                }
            }
            DatePicker("开始", selection: $start)
            DatePicker("结束", selection: $end)
            TextField("见面地点", text: $meeting)
            TextField("备注", text: $notes, axis: .vertical)
            Section("房源") {
                ForEach(candidateProperties) { property in
                    Toggle("\(property.communityName) \(property.doorText) · \(property.statusTitle)", isOn: Binding(
                        get: { selected.contains(property.id) },
                        set: { isOn in
                            isDirty = true
                            if isOn { selected.insert(property.id) } else { selected.remove(property.id) }
                        }
                    ))
                }
            }
        }
        .navigationTitle(existingID == nil ? "安排带看" : "改期")
        .navigationBarTitleDisplayMode(.inline)
        .formExitProtection(isDirty: isDirty)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("保存") { save() } } }
        .onAppear(perform: load)
        .onChange(of: meeting) { _, _ in isDirty = true }
        .errorAlert($errorMessage)
    }

    private var candidateProperties: [Property] {
        guard let need = needs.first(where: { $0.id == selectedNeed }) else { return [] }
        return properties.filter { BusinessRules.propertyIsViewable($0, for: need.kind) }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        selectedNeed = needID
        if let existing = viewings.first(where: { $0.id == existingID }) {
            selectedNeed = existing.clientNeed?.id
            start = existing.scheduledStart
            end = existing.scheduledEnd
            meeting = existing.meetingPoint
            notes = existing.notes
            selected = Set(existing.items.compactMap { $0.property?.id })
        }
    }

    private func save() {
        let ids = Array(selected)
        if let message = BusinessRules.validateViewing(start: start, end: end, propertyCount: ids.count, hasDuplicate: Set(ids).count != ids.count) {
            errorMessage = message
            return
        }
        guard let need = needs.first(where: { $0.id == selectedNeed }) else {
            errorMessage = "先选择需求。"
            return
        }
        let viewing = viewings.first { $0.id == existingID } ?? Viewing(scheduledStart: start, scheduledEnd: end)
        if existingID == nil { context.insert(viewing) }
        viewing.clientNeed = need
        viewing.scheduledStart = start
        viewing.scheduledEnd = end
        viewing.meetingPoint = BusinessRules.trimmed(meeting)
        viewing.notes = notes
        viewing.status = .scheduled
        viewing.updatedAt = Date()
        for item in viewing.items { context.delete(item) }
        for (index, id) in ids.enumerated() {
            let item = ViewingItem(sortOrder: index)
            item.viewing = viewing
            item.property = properties.first { $0.id == id }
            context.insert(item)
        }
        try? context.save()
        try? WorkflowService.sync(context: context)
        isDirty = false
        dismiss()
    }
}

struct ViewingDetailView: View {
    var viewingID: UUID
    @Query private var viewings: [Viewing]
    @Environment(\.modelContext) private var context
    @State private var editing = false
    private var viewing: Viewing? { viewings.first { $0.id == viewingID } }

    var body: some View {
        Group {
            if let viewing {
                List {
                    Section {
                        InfoRow(title: "客户", value: viewing.clientNeed?.contact?.displayName ?? "")
                        InfoRow(title: "开始", value: CNDate.dayTime(viewing.scheduledStart))
                        InfoRow(title: "结束", value: CNDate.dayTime(viewing.scheduledEnd))
                        InfoRow(title: "见面地点", value: viewing.meetingPoint)
                        InfoRow(title: "状态", value: viewing.status.title)
                        if !viewing.notes.isEmpty { Text(viewing.notes) }
                    }
                    Section("房源反馈") {
                        ForEach(viewing.sortedItems) { item in
                            ViewingItemEditor(item: item)
                        }
                    }
                    if viewing.status == .scheduled {
                        Section {
                            Button("改期") { editing = true }
                            Button("完成") { update(viewing, .completed) }
                            Button("取消", role: .destructive) { update(viewing, .cancelled) }
                        }
                    }
                }
                .navigationTitle("带看")
                .sheet(isPresented: $editing) {
                    NavigationStack { ViewingFormView(existingID: viewing.id, needID: viewing.clientNeed?.id) }
                }
            } else {
                EmptyStateView(title: "没有这场带看", message: "", systemImage: "figure.walk")
            }
        }
    }

    private func update(_ viewing: Viewing, _ status: ViewingStatus) {
        viewing.status = status
        viewing.updatedAt = Date()
        try? context.save()
        try? WorkflowService.sync(context: context)
    }
}

struct ViewingItemEditor: View {
    var item: ViewingItem
    @Environment(\.modelContext) private var context

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(item.property?.communityName ?? "") \(item.property?.doorText ?? "")")
                .font(.headline)
            Picker("兴趣", selection: Binding(
                get: { item.interest },
                set: { item.interest = $0; try? context.save() }
            )) {
                ForEach(ViewingInterest.allCases) { Text($0.title).tag($0) }
            }
            TextField("反馈", text: Binding(get: { item.feedback }, set: { item.feedback = $0 }))
            TextField("异议", text: Binding(get: { item.objections }, set: { item.objections = $0 }))
                .onSubmit { try? context.save() }
        }
    }
}
