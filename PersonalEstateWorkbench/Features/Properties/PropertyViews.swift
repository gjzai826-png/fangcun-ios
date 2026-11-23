import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct PropertyListView: View {
    @Query(sort: \Property.updatedAt, order: .reverse) private var properties: [Property]
    @Query(sort: \Community.name) private var communities: [Community]
    @State private var tab: PropertyBrowseTab = .sale
    @State private var query = ""
    @State private var filter = PropertyBrowseFilter()
    @State private var showFilter = false
    @State private var launch: FormLaunch?
    @State private var photoItem: PhotosPickerItem?
    @State private var recognized: RecognizedProperty?
    @State private var pendingPreset: RecognizedProperty?
    @State private var path = NavigationPath()
    @State private var errorMessage: String?

    private var visible: [Property] {
        PropertyService.sort(
            properties.filter { PropertyService.matches(tab: tab, property: $0, filter: filter, query: query) },
            by: filter.sort
        )
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("分类", selection: $tab) {
                        ForEach(PropertyBrowseTab.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    starredCommunities
                    if query.isEmpty && !StarStore.searchHistory.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(StarStore.searchHistory, id: \.self) { item in
                                    Button(item) {
                                        query = item
                                        StarStore.rememberSearch(item)
                                    }
                                    .buttonStyle(.bordered)
                                    .font(.caption)
                                }
                            }
                        }
                    }
                    if filter.isNarrowed {
                        Text("已筛选 · \(filter.sort.title)")
                            .font(.caption)
                            .foregroundStyle(Theme.accent)
                    }
                    let sections = PropertyService.sections(visible)
                    if sections.isEmpty {
                        EmptyStateView(title: "这里还没有房源", message: "非在租、在售和已暂定的房源会显示在「未挂牌」。", systemImage: "house")
                    }
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.subtitle.isEmpty ? section.title : "\(section.title) · \(section.subtitle)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.muted)
                            ForEach(section.properties) { property in
                                NavigationLink(value: RecordRoute.property(property.id)) {
                                    PropertyRow(property: property)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding()
            }
            .paperScreen()
            .navigationTitle("房源")
            .navigationDestination(for: RecordRoute.self) { RouteDestination(route: $0) }
            .searchable(text: $query, prompt: "楼栋、单元、房号")
            .onSubmit(of: .search) { StarStore.rememberSearch(query) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("筛选") { showFilter = true }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Image(systemName: "text.viewfinder")
                    }
                    .accessibilityLabel("截图识别")
                    Button {
                        launch = FormLaunch(listingKind: kindForNew, status: statusForNew)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("新建房源")
                }
            }
            .sheet(isPresented: $showFilter) {
                PropertyFilterSheet(tab: tab, filter: $filter, communities: communities)
            }
            .sheet(item: $launch) { item in
                NavigationStack {
                    PropertyFormView(existingID: item.existingID, preset: item.preset, listingKind: item.listingKind, status: item.status)
                }
            }
            .sheet(item: $recognized, onDismiss: {
                if let pendingPreset {
                    launch = FormLaunch(preset: pendingPreset, listingKind: pendingPreset.listingKind ?? .sale, status: .needsVerification)
                    self.pendingPreset = nil
                }
            }) { item in
                NavigationStack {
                    PropertyScreenshotReview(recognized: item) { confirmed in
                        pendingPreset = confirmed
                        recognized = nil
                    }
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        let result = await PropertyScreenshotRecognition.recognize(image, communities: communities)
                        recognized = result
                    } else {
                        errorMessage = "没有读到这张截图。"
                    }
                    photoItem = nil
                }
            }
            .errorAlert($errorMessage)
        }
    }

    private var kindForNew: ListingKind { tab == .rent ? .rent : .sale }
    private var statusForNew: PropertyStatus { tab == .unlisted ? .needsVerification : .available }

    @ViewBuilder
    private var starredCommunities: some View {
        let starred = communities.filter { StarStore.isStarred($0.id) && !$0.isArchived }
        if !starred.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(starred) { community in
                        Button(community.name) {
                            filter.communityID = filter.communityID == community.id ? nil : community.id
                        }
                        .buttonStyle(.bordered)
                        .tint(filter.communityID == community.id ? Theme.accent : Theme.muted)
                    }
                }
            }
        }
    }
}

struct FormLaunch: Identifiable {
    var id = UUID()
    var existingID: UUID?
    var preset: RecognizedProperty?
    var listingKind: ListingKind = .sale
    var status: PropertyStatus = .available
}

struct PropertyFilterSheet: View {
    var tab: PropertyBrowseTab
    @Binding var filter: PropertyBrowseFilter
    var communities: [Community]
    @Environment(\.dismiss) private var dismiss
    @State private var minText = ""
    @State private var maxText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("排序", selection: $filter.sort) {
                        ForEach(PropertyBrowseSort.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("小区", selection: $filter.communityID) {
                        Text("全部").tag(UUID?.none)
                        ForEach(communities.filter { !$0.isArchived }) { community in
                            Text(community.name).tag(Optional(community.id))
                        }
                    }
                    TextField("区域", text: $filter.district)
                    TextField(tab == .rent ? "最低月租（元）" : "最低总价（万元）", text: $minText).keyboardType(.decimalPad)
                    TextField(tab == .rent ? "最高月租（元）" : "最高总价（万元）", text: $maxText).keyboardType(.decimalPad)
                }
                Section {
                    Picker("室", selection: $filter.bedrooms) {
                        Text("不限").tag(Int?.none)
                        ForEach(1..<7, id: \.self) { Text("\($0)室").tag(Optional($0)) }
                    }
                    Picker("状态", selection: $filter.status) {
                        Text("不限").tag(PropertyStatus?.none)
                        ForEach(PropertyStatus.allCases) { status in
                            Text(status.title(for: tab == .rent ? .rent : .sale)).tag(Optional(status))
                        }
                    }
                    TextField("楼栋", text: $filter.building)
                    TextField("单元", text: $filter.unit)
                    TextField("房号", text: $filter.room)
                }
                Section {
                    Toggle("包含已归档", isOn: $filter.includeArchived)
                    Toggle("只看近 7 天更新", isOn: $filter.recentOnly)
                    Toggle("只看有照片", isOn: $filter.photosOnly)
                    Toggle("只看有电梯", isOn: $filter.elevatorOnly)
                }
            }
            .navigationTitle("筛选")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { apply(); dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("清除") { filter = PropertyBrowseFilter(); minText = ""; maxText = "" }
                }
            }
        }
    }

    private func apply() {
        let kind: ListingKind = tab == .rent ? .rent : .sale
        filter.priceMin = Money.parse(minText, kind: kind)
        filter.priceMax = Money.parse(maxText, kind: kind)
    }
}

struct PropertyDraft: Equatable {
    var communityID: UUID?
    var building = ""
    var unit = ""
    var room = ""
    var listingKind: ListingKind = .sale
    var status: PropertyStatus = .available
    var priceText = ""
    var hasAvailableFrom = false
    var availableFrom = Date()
    var viewingMethod = ""
    var bedrooms = 0
    var livingRooms = 0
    var bathrooms = 0
    var areaText = ""
    var floorText = ""
    var totalFloorsText = ""
    var orientation = ""
    var decoration = ""
    var hasElevator = false
    var featureText = ""
    var fee: PropertyFeeOption = .unspecified
    var parking: ParkingOption = .unspecified
    var ownerID: UUID?
    var internalNotes = ""
    var statusReason = ""
    var latitudeText = ""
    var longitudeText = ""

    static func from(_ property: Property) -> PropertyDraft {
        var draft = PropertyDraft()
        draft.communityID = property.community?.id
        draft.building = property.building
        draft.unit = property.unit
        draft.room = property.room
        draft.listingKind = property.listingKind
        draft.status = property.status
        if property.askingPriceCents > 0 {
            draft.priceText = property.listingKind == .sale
                ? Money.wan(fromCents: property.askingPriceCents).formatted(.number.precision(.fractionLength(0...2)))
                : Money.yuan(fromCents: property.askingPriceCents).formatted(.number.precision(.fractionLength(0...2)))
        }
        if let date = property.availableFrom {
            draft.hasAvailableFrom = true
            draft.availableFrom = date
        }
        draft.viewingMethod = property.viewingMethod
        draft.bedrooms = property.bedrooms
        draft.livingRooms = property.livingRooms
        draft.bathrooms = property.bathrooms
        if property.area > 0 { draft.areaText = String(property.area) }
        if property.floor > 0 { draft.floorText = String(property.floor) }
        if property.totalFloors > 0 { draft.totalFloorsText = String(property.totalFloors) }
        draft.orientation = property.orientation
        draft.decoration = property.decoration
        draft.hasElevator = property.hasElevator
        draft.featureText = property.features.filter { !FeatureToken.feeTokens.contains($0) && !FeatureToken.parkingTokens.contains($0) }.joined(separator: "、")
        draft.fee = FeatureToken.fee(in: property.features)
        draft.parking = FeatureToken.parking(in: property.features)
        draft.ownerID = property.owner?.id
        draft.internalNotes = property.internalNotes
        draft.latitudeText = property.community?.latitude.map { String($0) } ?? ""
        draft.longitudeText = property.community?.longitude.map { String($0) } ?? ""
        return draft
    }

    static func from(_ recognized: RecognizedProperty, fallbackKind: ListingKind, fallbackStatus: PropertyStatus) -> PropertyDraft {
        var draft = PropertyDraft()
        draft.communityID = recognized.communityID
        draft.listingKind = recognized.listingKind ?? fallbackKind
        draft.status = fallbackStatus
        if let cents = recognized.askingPriceCents, cents > 0 {
            draft.priceText = draft.listingKind == .sale
                ? Money.wan(fromCents: cents).formatted(.number.precision(.fractionLength(0...2)))
                : Money.yuan(fromCents: cents).formatted(.number.precision(.fractionLength(0...2)))
        }
        draft.bedrooms = recognized.bedrooms ?? 0
        draft.livingRooms = recognized.livingRooms ?? 0
        draft.bathrooms = recognized.bathrooms ?? 0
        if let area = recognized.area { draft.areaText = String(area) }
        if let floor = recognized.floor { draft.floorText = String(floor) }
        if let total = recognized.totalFloors { draft.totalFloorsText = String(total) }
        draft.orientation = recognized.orientation ?? ""
        draft.decoration = recognized.decoration ?? ""
        draft.hasElevator = recognized.hasElevator ?? false
        return draft
    }
}

struct PropertyFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Community.name) private var communities: [Community]
    @Query(sort: \Contact.displayName) private var contacts: [Contact]

    var existingID: UUID?
    var preset: RecognizedProperty?
    var listingKind: ListingKind
    var status: PropertyStatus

    @State private var draft = PropertyDraft()
    @State private var originalStatus: PropertyStatus?
    @State private var isDirty = false
    @State private var didLoad = false
    @State private var errorMessage: String?
    @State private var warning: String?
    @State private var showCommunity = false
    @State private var showOwner = false
    @State private var suggestedCommunity = ""

    var body: some View {
        Form {
            Section("小区") {
                Picker("小区", selection: field(\.communityID)) {
                    Text("请选择").tag(UUID?.none)
                    ForEach(communities.filter { !$0.isArchived || $0.id == draft.communityID }) { community in
                        Text(community.name).tag(Optional(community.id))
                    }
                }
                Button("新建小区") {
                    suggestedCommunity = preset?.suggestedCommunityName ?? ""
                    showCommunity = true
                }
                TextField("楼栋", text: field(\.building))
                TextField("单元", text: field(\.unit))
                TextField("房号", text: field(\.room))
            }
            Section("挂牌") {
                Picker("租售", selection: field(\.listingKind)) {
                    ForEach(ListingKind.allCases) { Text($0.title).tag($0) }
                }
                Picker("状态", selection: field(\.status)) {
                    ForEach(PropertyStatus.allCases) { Text($0.title(for: draft.listingKind)).tag($0) }
                }
                TextField(draft.listingKind == .sale ? "报价（万元）" : "月租（元）", text: field(\.priceText))
                    .keyboardType(.decimalPad)
                TextField("看房方式", text: field(\.viewingMethod))
                Toggle("填写可入住日期", isOn: field(\.hasAvailableFrom))
                if draft.hasAvailableFrom {
                    DatePicker("可入住", selection: field(\.availableFrom), displayedComponents: .date)
                }
                if originalStatus != nil && draft.status != originalStatus {
                    TextField("状态变更原因", text: field(\.statusReason))
                }
            }
            Section("户型物业") {
                Stepper("室 \(draft.bedrooms)", value: field(\.bedrooms), in: 0...10)
                Stepper("厅 \(draft.livingRooms)", value: field(\.livingRooms), in: 0...10)
                Stepper("卫 \(draft.bathrooms)", value: field(\.bathrooms), in: 0...10)
                TextField("面积（㎡）", text: field(\.areaText)).keyboardType(.decimalPad)
                TextField("楼层", text: field(\.floorText)).keyboardType(.numberPad)
                TextField("总层", text: field(\.totalFloorsText)).keyboardType(.numberPad)
                Picker("朝向", selection: field(\.orientation)) {
                    Text("未填").tag("")
                    ForEach(OrientationOption.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Picker("装修", selection: field(\.decoration)) {
                    Text("未填").tag("")
                    ForEach(DecorationOption.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Toggle("有电梯", isOn: field(\.hasElevator))
                TextField("其他特征，顿号分隔", text: field(\.featureText))
                Picker("物业费", selection: field(\.fee)) {
                    ForEach(PropertyFeeOption.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("propertyFeePicker")
                Picker("车位", selection: field(\.parking)) {
                    ForEach(ParkingOption.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("propertyParkingPicker")
            }
            Section("业主与备注") {
                Picker("业主", selection: field(\.ownerID)) {
                    Text("暂不填写").tag(UUID?.none)
                    ForEach(contacts.filter { !$0.isArchived || $0.id == draft.ownerID }) { contact in
                        Text(contact.displayName).tag(Optional(contact.id))
                    }
                }
                Button("新建业主") { showOwner = true }
                TextField("内部备注，不进入对外分享", text: field(\.internalNotes), axis: .vertical)
            }
            Section("坐标，可选") {
                TextField("纬度", text: field(\.latitudeText)).keyboardType(.decimalPad)
                TextField("经度", text: field(\.longitudeText)).keyboardType(.decimalPad)
                Text("没有地图页。坐标只是随小区保存，方便以后换机。")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
        }
        .navigationTitle(existingID == nil ? "新建房源" : "编辑房源")
        .navigationBarTitleDisplayMode(.inline)
        .formExitProtection(isDirty: isDirty)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save(force: false) }
                    .accessibilityIdentifier("savePropertyButton")
            }
        }
        .onAppear(perform: load)
        .sheet(isPresented: $showCommunity) {
            NavigationStack { CommunityFormView(suggestedName: suggestedCommunity) { draft.communityID = $0; isDirty = true } }
        }
        .sheet(isPresented: $showOwner) {
            NavigationStack { ContactFormView(lockedRoles: [.owner]) { draft.ownerID = $0; isDirty = true } }
        }
        .errorAlert($errorMessage)
        .alert("请再确认", isPresented: Binding(get: { warning != nil }, set: { if !$0 { warning = nil } })) {
            Button("仍然保存") { save(force: true) }
            Button("返回修改", role: .cancel) {}
        } message: { Text(warning ?? "") }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        if let existingID, let property = properties.first(where: { $0.id == existingID }) {
            draft = .from(property)
            originalStatus = property.status
        } else if let preset {
            draft = .from(preset, fallbackKind: listingKind, fallbackStatus: status)
            isDirty = true
        } else {
            draft.listingKind = listingKind
            draft.status = status
        }
    }

    private var properties: [Property] {
        (try? context.all(Property.self)) ?? []
    }

    private func field<T: Equatable>(_ keyPath: WritableKeyPath<PropertyDraft, T>) -> Binding<T> {
        Binding(
            get: { draft[keyPath: keyPath] },
            set: { newValue in
                if draft[keyPath: keyPath] != newValue { isDirty = true }
                draft[keyPath: keyPath] = newValue
            }
        )
    }

    private func save(force: Bool) {
        if let message = BusinessRules.validateProperty(hasCommunity: draft.communityID != nil) {
            errorMessage = message
            return
        }
        let changed = originalStatus != nil && draft.status != originalStatus
        if let message = BusinessRules.validateStatusChange(changed: changed, reason: draft.statusReason) {
            errorMessage = message
            return
        }
        guard let community = communities.first(where: { $0.id == draft.communityID }) else {
            errorMessage = "小区必填，其他内容可以后补。"
            return
        }
        if !force {
            let sameName = communities.filter { $0.id != community.id && $0.name == community.name }.count
            if let message = BusinessRules.duplicateCommunityWarning(name: community.name, others: sameName) {
                warning = message
                return
            }
        }
        let property: Property
        if let existingID, let existing = properties.first(where: { $0.id == existingID }) {
            property = existing
        } else {
            property = Property()
            context.insert(property)
        }
        property.community = community
        property.building = BusinessRules.trimmed(draft.building)
        property.unit = BusinessRules.trimmed(draft.unit)
        property.room = BusinessRules.trimmed(draft.room)
        property.listingKind = draft.listingKind
        property.askingPriceCents = Money.parse(draft.priceText, kind: draft.listingKind) ?? 0
        property.availableFrom = draft.hasAvailableFrom ? draft.availableFrom : nil
        property.viewingMethod = BusinessRules.trimmed(draft.viewingMethod)
        property.bedrooms = draft.bedrooms
        property.livingRooms = draft.livingRooms
        property.bathrooms = draft.bathrooms
        property.area = Double(draft.areaText) ?? 0
        property.floor = Int(draft.floorText) ?? 0
        property.totalFloors = Int(draft.totalFloorsText) ?? 0
        property.orientation = draft.orientation
        property.decoration = draft.decoration
        property.hasElevator = draft.hasElevator
        property.features = FeatureToken.replacing(
            features: BusinessRules.splitList(draft.featureText),
            fee: draft.fee,
            parking: draft.parking
        )
        property.owner = contacts.first { $0.id == draft.ownerID }
        if let owner = property.owner, !owner.roles.contains(.owner) {
            owner.roles.append(.owner)
        }
        property.internalNotes = BusinessRules.trimmed(draft.internalNotes)
        if let latitude = Double(draft.latitudeText) { community.latitude = latitude }
        if let longitude = Double(draft.longitudeText) { community.longitude = longitude }
        community.updatedAt = Date()
        if let originalStatus, originalStatus != draft.status {
            PropertyService.recordStatusChange(of: property, to: draft.status, reason: BusinessRules.trimmed(draft.statusReason))
        } else if originalStatus == nil {
            property.status = draft.status
        }
        property.updatedAt = Date()
        do {
            try context.save()
            try? WorkflowService.sync(context: context)
            isDirty = false
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
