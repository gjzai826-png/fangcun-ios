import SwiftData
import SwiftUI

struct ContactListView: View {
    @Query(sort: \Contact.displayName) private var contacts: [Contact]
    @State private var query = ""
    @State private var creating = false

    private var visible: [Contact] {
        contacts.filter { contact in
            guard !contact.isArchived else { return false }
            if query.isEmpty { return true }
            let digits = BusinessRules.digits(query)
            if digits.count >= 3 && BusinessRules.digits(contact.phone).contains(digits) { return true }
            return contact.displayName.localizedCaseInsensitiveContains(query) || contact.wechat.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        List(visible) { contact in
            NavigationLink(value: RecordRoute.contact(contact.id)) {
                VStack(alignment: .leading) {
                    Text(contact.displayName)
                    Text(contact.roleTitle).font(.caption).foregroundStyle(Theme.muted)
                }
            }
        }
        .navigationTitle("联系人")
        .searchable(text: $query, prompt: "称呼、电话或微信")
        .toolbar { Button("新建") { creating = true } }
        .sheet(isPresented: $creating) { NavigationStack { ContactFormView() } }
        .overlay { if visible.isEmpty { EmptyStateView(title: "还没有联系人", message: "可以只保存称呼，电话和微信以后再补。", systemImage: "person") } }
    }
}

struct ContactDetailView: View {
    var contactID: UUID
    @Query private var contacts: [Contact]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var addingNeed = false
    @State private var confirmDelete = false
    private var contact: Contact? { contacts.first { $0.id == contactID } }

    var body: some View {
        Group {
            if let contact {
                List {
                    Section {
                        InfoRow(title: "电话", value: contact.phone)
                        InfoRow(title: "微信", value: contact.wechat)
                        InfoRow(title: "角色", value: contact.roleTitle)
                        if !contact.notes.isEmpty { Text(contact.notes) }
                        if !contact.phone.isEmpty { Button("拨打") { ContactActions.call(contact.phone) } }
                        if !contact.wechat.isEmpty { Button("复制微信并打开微信") { ContactActions.openWeChat(contact.wechat) } }
                    }
                    Section("需求") {
                        ForEach(contact.clientNeeds) { need in
                            NavigationLink(value: RecordRoute.need(need.id)) {
                                Text("\(need.kind.title) · \(need.status.title) · \(need.budgetText)")
                            }
                        }
                        Button("为这个联系人新增需求") { addingNeed = true }
                    }
                    Section("名下房源") {
                        ForEach(contact.ownedProperties) { property in
                            NavigationLink(value: RecordRoute.property(property.id)) {
                                Text("\(property.communityName) \(property.doorText)")
                            }
                        }
                    }
                    Section {
                        Button("删除客户", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("相关提醒会取消。房源、房源跟进和成交记录保留。如果同时也是业主，业主资料会留下。")
                    }
                }
                .navigationTitle(contact.displayName)
                .toolbar { Button("编辑") { editing = true } }
                .sheet(isPresented: $editing) { NavigationStack { ContactFormView(existingID: contact.id) } }
                .sheet(isPresented: $addingNeed) { NavigationStack { ClientNeedFormView(contactID: contact.id) } }
                .confirmationDialog("删除这个客户？", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("删除", role: .destructive) {
                        WorkflowService.deleteContact(contact, context: context)
                        try? context.save()
                        dismiss()
                    }
                }
            } else {
                EmptyStateView(title: "没有这个联系人", message: "", systemImage: "person")
            }
        }
    }
}

struct ContactFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var contacts: [Contact]
    var existingID: UUID?
    var lockedRoles: [ContactRole] = []
    var onSaved: (UUID) -> Void = { _ in }

    @State private var name = ""
    @State private var phone = ""
    @State private var wechat = ""
    @State private var notes = ""
    @State private var roles: Set<ContactRole> = []
    @State private var isDirty = false
    @State private var didLoad = false
    @State private var errorMessage: String?
    @State private var warning: String?

    var body: some View {
        Form {
            TextField("称呼", text: $name)
            TextField("电话，可后补", text: $phone).keyboardType(.phonePad)
            TextField("微信，可后补", text: $wechat)
            TextField("备注", text: $notes, axis: .vertical)
            Section("角色") {
                ForEach(ContactRole.allCases) { role in
                    Toggle(role.title, isOn: Binding(
                        get: { roles.contains(role) },
                        set: { isOn in
                            isDirty = true
                            if isOn { roles.insert(role) } else { roles.remove(role) }
                        }
                    ))
                }
            }
        }
        .navigationTitle(existingID == nil ? "新建联系人" : "编辑联系人")
        .navigationBarTitleDisplayMode(.inline)
        .formExitProtection(isDirty: isDirty)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("保存") { save(force: false) } } }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            if let existing = contacts.first(where: { $0.id == existingID }) {
                name = existing.displayName
                phone = existing.phone
                wechat = existing.wechat
                notes = existing.notes
                roles = Set(existing.roles)
            }
            roles.formUnion(lockedRoles)
        }
        .onChange(of: name) { _, _ in isDirty = true }
        .onChange(of: phone) { _, _ in isDirty = true }
        .errorAlert($errorMessage)
        .alert("可能重复", isPresented: Binding(get: { warning != nil }, set: { if !$0 { warning = nil } })) {
            Button("仍然保存") { save(force: true) }
            Button("返回修改", role: .cancel) {}
        } message: { Text(warning ?? "") }
    }

    private func save(force: Bool) {
        if let message = BusinessRules.validateContact(name: name, phone: phone, wechat: wechat) {
            errorMessage = message
            return
        }
        let digits = BusinessRules.digits(phone)
        let others = contacts.filter { $0.id != existingID && BusinessRules.digits($0.phone) == digits }.count
        if !force, let message = BusinessRules.duplicatePhoneWarning(phone: phone, others: others) {
            warning = message
            return
        }
        let contact = contacts.first { $0.id == existingID } ?? Contact(displayName: BusinessRules.trimmed(name))
        if existingID == nil { context.insert(contact) }
        contact.displayName = BusinessRules.trimmed(name)
        contact.phone = BusinessRules.trimmed(phone)
        contact.wechat = BusinessRules.trimmed(wechat)
        contact.notes = BusinessRules.trimmed(notes)
        contact.roles = Array(roles)
        contact.updatedAt = Date()
        try? context.save()
        isDirty = false
        onSaved(contact.id)
        dismiss()
    }
}
