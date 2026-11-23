import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct DealListView: View {
    @Query(sort: \Deal.signedOn, order: .reverse) private var deals: [Deal]
    private var totals: (saleCents: Int, rentCents: Int, receivedCents: Int) { DealService.performance(deals: deals) }

    var body: some View {
        List {
            Section {
                Text("买卖总价合计 \(Money.saleText(totals.saleCents))")
                Text("租赁月租合计 \(Money.rentText(totals.rentCents))")
                Text("已收佣金 \(Money.yuanText(totals.receivedCents)) 元")
            } footer: { Text("不含已作废。行情参考不在这里。") }
            ForEach(deals) { deal in
                NavigationLink(value: RecordRoute.deal(deal.id)) {
                    VStack(alignment: .leading) {
                        Text("\(deal.kind.title) · \(deal.priceText)")
                        Text("\(deal.communityNameSnapshot) · \(deal.status.title)").font(.caption).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .navigationTitle("个人成交")
    }
}

struct DealDetailView: View {
    var dealID: UUID
    @Query private var deals: [Deal]
    @Environment(\.modelContext) private var context
    @State private var editing = false
    @State private var voiding = false
    @State private var voidReason = ""
    @State private var renewing = false
    @State private var ending = false
    @State private var message: String?
    private var deal: Deal? { deals.first { $0.id == dealID } }

    var body: some View {
        Group {
            if let deal {
                List {
                    Section {
                        InfoRow(title: "成交编号", value: deal.displayNumber)
                        InfoRow(title: "类型", value: deal.kind.title)
                        InfoRow(title: "状态", value: deal.status.title)
                        InfoRow(title: "签约日期", value: CNDate.day(deal.signedOn))
                        InfoRow(title: deal.kind == .sale ? "实际总价" : "实际月租", value: deal.priceText)
                        InfoRow(title: "应收佣金", value: Money.yuanText(deal.commissionReceivableCents) + " 元")
                        InfoRow(title: "已收佣金", value: Money.yuanText(deal.commissionReceivedCents) + " 元")
                        if let start = deal.leaseStartOn { InfoRow(title: "租约开始", value: CNDate.day(start)) }
                        if let end = deal.leaseEndOn { InfoRow(title: "租约结束", value: CNDate.day(end)) }
                        InfoRow(title: "小区快照", value: deal.communityNameSnapshot)
                        InfoRow(title: "房源快照", value: deal.propertyDescriptionSnapshot)
                        InfoRow(title: "对方快照", value: deal.counterpartyNameSnapshot)
                        if !deal.notes.isEmpty { Text(deal.notes) }
                        if !deal.voidReason.isEmpty { InfoRow(title: "作废原因", value: deal.voidReason) }
                    }
                    if deal.status == .active {
                        Section {
                            Button("成交更正") { editing = true }
                            if deal.kind == .rent {
                                Button("续租") { renewing = true }
                                Button("已退租") { ending = true }
                            }
                            Button("另存为行情参考") { saveComparable(deal) }
                            Button("作废", role: .destructive) { voiding = true }
                        } footer: {
                            Text("更正会保留历史快照和原成交编号。作废后不能直接恢复，房源转为待核实，不会自动上架。行情参考不计入个人业绩。")
                        }
                    }
                }
                .navigationTitle("成交")
                .sheet(isPresented: $editing) { NavigationStack { DealFormView(propertyID: deal.property?.id ?? UUID(), existingDealID: deal.id) } }
                .sheet(isPresented: $renewing) { NavigationStack { DealFormView(propertyID: deal.property?.id ?? UUID(), renewFrom: deal.id) } }
                .alert("作废原因", isPresented: $voiding) {
                    TextField("原因", text: $voidReason)
                    Button("作废", role: .destructive) {
                        guard !BusinessRules.trimmed(voidReason).isEmpty else { return }
                        DealService.void(deal, reason: voidReason)
                        try? context.save()
                        try? WorkflowService.sync(context: context)
                    }
                    Button("取消", role: .cancel) {}
                } message: { Text("作废后不能直接恢复。") }
                .confirmationDialog("已退租，房源待检查", isPresented: $ending, titleVisibility: .visible) {
                    Button("确认退租", role: .destructive) {
                        DealService.endLease(deal)
                        try? context.save()
                        try? WorkflowService.sync(context: context)
                    }
                } message: { Text("房源会转为待核实，没有自动上架。") }
                .alert("已另存", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                    Button("好") {}
                } message: { Text(message ?? "") }
            } else {
                EmptyStateView(title: "没有这笔成交", message: "", systemImage: "signature")
            }
        }
    }

    private func saveComparable(_ deal: Deal) {
        guard let comparable = DealService.makeComparable(from: deal) else { return }
        context.insert(comparable)
        try? context.save()
        message = "已写入行情，不计入业绩合计。这笔个人成交仍然保留。"
    }
}

struct DealFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var properties: [Property]
    @Query private var contacts: [Contact]
    @Query private var needs: [ClientNeed]
    @Query private var deals: [Deal]

    var propertyID: UUID
    var existingDealID: UUID?
    var renewFrom: UUID?

    @State private var signed = Date()
    @State private var price = ""
    @State private var receivable = ""
    @State private var received = ""
    @State private var leaseStart = Date()
    @State private var leaseEnd = Date().addingTimeInterval(86400 * 365)
    @State private var notes = ""
    @State private var contactID: UUID?
    @State private var needID: UUID?
    @State private var useFormula = false
    @State private var photoFee = false
    @State private var propertyFee = false
    @State private var keyFee = false
    @State private var followPercent = 0
    @State private var isDirty = false
    @State private var didLoad = false
    @State private var errorMessage: String?

    private var property: Property? { properties.first { $0.id == propertyID } }
    private var kind: DealKind { property?.listingKind == .rent ? .rent : .sale }

    var body: some View {
        Form {
            if let property {
                LabeledContent("房源", value: "\(property.communityName) \(property.doorText)")
                LabeledContent("类型", value: kind.title)
            }
            DatePicker("签约日期", selection: $signed, displayedComponents: .date)
            TextField(kind == .sale ? "实际总价（万元）" : "实际月租（元）", text: $price).keyboardType(.decimalPad)
            if kind == .rent {
                DatePicker("租约开始", selection: $leaseStart, displayedComponents: .date)
                DatePicker("租约结束", selection: $leaseEnd, displayedComponents: .date)
            }
            Picker("对方", selection: $contactID) {
                Text("未选").tag(UUID?.none)
                ForEach(contacts) { Text($0.displayName).tag(Optional($0.id)) }
            }
            Picker("关联需求", selection: $needID) {
                Text("不关联").tag(UUID?.none)
                ForEach(needs) { Text($0.contact?.displayName ?? $0.kind.title).tag(Optional($0.id)) }
            }
            TextField("备注", text: $notes, axis: .vertical)
            Section("佣金") {
                TextField("应收（元）", text: $receivable).keyboardType(.decimalPad)
                TextField("已收（元）", text: $received).keyboardType(.decimalPad)
                Toggle("使用分佣估算", isOn: $useFormula)
                if useFormula {
                    Text("分佣基数：成交价 × 80%。到手佣金：扣除所选费用后 × 80%。这是按文案做的估算，默认不写入。")
                        .font(.footnote).foregroundStyle(Theme.muted)
                    Toggle("图片费 2%", isOn: $photoFee)
                    Toggle("房源费 12%", isOn: $propertyFee)
                    Toggle("钥匙费 5%", isOn: $keyFee)
                    Picker("跟进费", selection: $followPercent) {
                        Text("不分佣").tag(0)
                        Text("1%").tag(1)
                        Text("3%").tag(3)
                        Text("4%").tag(4)
                    }
                    Button("按公式填入应收") { fillReceivable() }
                }
            }
        }
        .navigationTitle(existingDealID == nil ? (renewFrom == nil ? "登记成交" : "续租") : "成交更正")
        .navigationBarTitleDisplayMode(.inline)
        .formExitProtection(isDirty: isDirty)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("保存") { save() } } }
        .onAppear(perform: load)
        .onChange(of: price) { _, _ in isDirty = true }
        .errorAlert($errorMessage)
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        contactID = property?.owner?.id
        if let existing = deals.first(where: { $0.id == existingDealID }) {
            signed = existing.signedOn
            price = existing.kind == .sale ? String(Money.wan(fromCents: existing.actualPriceCents)) : String(Money.yuan(fromCents: existing.actualPriceCents))
            receivable = String(Money.yuan(fromCents: existing.commissionReceivableCents))
            received = String(Money.yuan(fromCents: existing.commissionReceivedCents))
            leaseStart = existing.leaseStartOn ?? leaseStart
            leaseEnd = existing.leaseEndOn ?? leaseEnd
            notes = existing.notes
            contactID = existing.contact?.id
            needID = existing.clientNeed?.id
            if let allocation = existing.commissionAllocation {
                useFormula = true
                photoFee = allocation.photoFee
                propertyFee = allocation.propertyFee
                keyFee = allocation.keyFee
                followPercent = allocation.followUpPercent
            }
        }
    }

    private func priceCents() -> Int {
        guard let value = Double(price) else { return 0 }
        return kind == .sale ? Money.cents(fromWan: value) : Money.cents(fromYuan: value)
    }

    private func fillReceivable() {
        let allocation = DealCommissionAllocation(propertyFee: propertyFee, photoFee: photoFee, keyFee: keyFee, followUpPercent: followPercent)
        let cents = DealService.estimatedReceivable(priceCents: priceCents(), allocation: allocation)
        receivable = String(Money.yuan(fromCents: cents))
    }

    private func save() {
        guard let property else { errorMessage = "房源不在了。"; return }
        let cents = priceCents()
        let ranges = kind == .rent ? DealService.otherActiveLeaseRanges(property: property, excluding: existingDealID) : []
        if let message = BusinessRules.validateDeal(
            kind: kind, property: property, priceCents: cents,
            leaseStart: kind == .rent ? leaseStart : nil,
            leaseEnd: kind == .rent ? leaseEnd : nil,
            otherLeaseRanges: ranges
        ) {
            errorMessage = message
            return
        }
        let deal: Deal
        let isNew = existingDealID == nil
        if let existing = deals.first(where: { $0.id == existingDealID }) {
            deal = existing
        } else {
            deal = Deal(kind: kind, actualPriceCents: cents)
            context.insert(deal)
        }
        deal.kind = kind
        deal.signedOn = signed
        deal.actualPriceCents = cents
        deal.commissionReceivableCents = Money.cents(fromYuan: Double(receivable) ?? 0)
        deal.commissionReceivedCents = Money.cents(fromYuan: Double(received) ?? 0)
        deal.leaseStartOn = kind == .rent ? leaseStart : nil
        deal.leaseEndOn = kind == .rent ? leaseEnd : nil
        deal.notes = notes
        deal.property = property
        deal.contact = contacts.first { $0.id == contactID }
        deal.clientNeed = needs.first { $0.id == needID }
        deal.updatedAt = Date()
        if isNew {
            DealService.fillSnapshots(deal, property: property, contact: deal.contact)
            DealService.markRegistered(deal, property: property)
        }
        if useFormula {
            let allocation = deal.commissionAllocation ?? DealCommissionAllocation()
            if deal.commissionAllocation == nil {
                allocation.deal = deal
                context.insert(allocation)
            }
            allocation.photoFee = photoFee
            allocation.propertyFee = propertyFee
            allocation.keyFee = keyFee
            allocation.followUpPercent = followPercent
        }
        try? context.save()
        try? WorkflowService.sync(context: context)
        isDirty = false
        dismiss()
    }
}

struct MarketListView: View {
    @Query(sort: \MarketComparable.dealDate, order: .reverse) private var items: [MarketComparable]
    @State private var creating = false

    var body: some View {
        List(items) { item in
            NavigationLink(value: RecordRoute.comparable(item.id)) {
                VStack(alignment: .leading) {
                    Text("\(item.community?.name ?? "未选小区") · \(Money.priceText(item.priceCents, kind: item.kind))")
                    Text("\(CNDate.day(item.dealDate)) · \(item.sourceDescription)").font(.caption).foregroundStyle(Theme.muted)
                }
            }
        }
        .navigationTitle("行情")
        .toolbar { Button("记一笔") { creating = true } }
        .sheet(isPresented: $creating) { NavigationStack { MarketFormView() } }
        .overlay {
            if items.isEmpty {
                EmptyStateView(title: "还没有行情", message: "这里记别人的真实成交，不计入个人业绩。", systemImage: "chart.line.uptrend.xyaxis")
            }
        }
    }
}

struct MarketDetailView: View {
    var comparableID: UUID
    @Query private var items: [MarketComparable]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    private var item: MarketComparable? { items.first { $0.id == comparableID } }

    var body: some View {
        Group {
            if let item {
                List {
                    Section {
                        InfoRow(title: "小区", value: item.community?.name ?? "")
                        InfoRow(title: "类型", value: item.kind.title)
                        InfoRow(title: "日期", value: CNDate.day(item.dealDate))
                        InfoRow(title: "价格", value: Money.priceText(item.priceCents, kind: item.kind))
                        InfoRow(title: "面积", value: item.area > 0 ? "\(item.area)㎡" : "")
                        InfoRow(title: "室", value: item.bedrooms > 0 ? "\(item.bedrooms)" : "")
                        InfoRow(title: "装修", value: item.decoration)
                        InfoRow(title: "楼层", value: item.floorDescription)
                        InfoRow(title: "来源", value: item.sourceDescription)
                        if !item.notes.isEmpty { Text(item.notes) }
                    }
                    Section {
                    Button("删除", role: .destructive) {
                        for asset in item.evidenceAssets { MediaStore.deleteFiles(for: asset) }
                        context.delete(item)
                        try? context.save()
                        dismiss()
                    }
                    }
                }
                .navigationTitle("行情参考")
                .toolbar { Button("编辑") { editing = true } }
                .sheet(isPresented: $editing) { NavigationStack { MarketFormView(existingID: item.id) } }
            } else {
                EmptyStateView(title: "没有这条行情", message: "", systemImage: "chart.line.uptrend.xyaxis")
            }
        }
    }
}

struct MarketFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var communities: [Community]
    @Query private var items: [MarketComparable]
    var existingID: UUID?
    @State private var communityID: UUID?
    @State private var kind: ListingKind = .sale
    @State private var date = Date()
    @State private var price = ""
    @State private var area = ""
    @State private var bedrooms = ""
    @State private var decoration = ""
    @State private var floor = ""
    @State private var source = ""
    @State private var notes = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var isDirty = false
    @State private var didLoad = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Picker("小区", selection: $communityID) {
                Text("请选择").tag(UUID?.none)
                ForEach(communities) { Text($0.name).tag(Optional($0.id)) }
            }
            Picker("类型", selection: $kind) { ForEach(ListingKind.allCases) { Text($0.title).tag($0) } }
            DatePicker("日期", selection: $date, displayedComponents: .date)
            TextField(kind == .sale ? "价格（万元）" : "月租（元）", text: $price).keyboardType(.decimalPad)
            TextField("面积", text: $area).keyboardType(.decimalPad)
            TextField("室", text: $bedrooms).keyboardType(.numberPad)
            Picker("装修", selection: $decoration) {
                Text("未填").tag("")
                ForEach(DecorationOption.allCases) { Text($0.title).tag($0.rawValue) }
            }
            TextField("楼层描述", text: $floor)
            Section {
                TextField("来源", text: $source)
                TextField("备注", text: $notes, axis: .vertical)
                if existingID == nil {
                    Text("先保存这条行情，再添加证据照片。")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                } else {
                    PhotosPicker(selection: $photoItem, matching: .images) { Text("添加证据照片") }
                }
            }
        }
        .navigationTitle(existingID == nil ? "记一笔行情" : "编辑行情")
        .navigationBarTitleDisplayMode(.inline)
        .formExitProtection(isDirty: isDirty)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("保存") { save() } } }
        .onAppear(perform: load)
        .onChange(of: price) { _, _ in isDirty = true }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await attach(item) }
        }
        .errorAlert($errorMessage)
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        guard let existing = items.first(where: { $0.id == existingID }) else { return }
        communityID = existing.community?.id
        kind = existing.kind
        date = existing.dealDate
        price = kind == .sale ? String(Money.wan(fromCents: existing.priceCents)) : String(Money.yuan(fromCents: existing.priceCents))
        area = existing.area > 0 ? String(existing.area) : ""
        bedrooms = existing.bedrooms > 0 ? String(existing.bedrooms) : ""
        decoration = existing.decoration
        floor = existing.floorDescription
        source = existing.sourceDescription
        notes = existing.notes
    }

    private func attach(_ item: PhotosPickerItem) async {
        guard let existing = items.first(where: { $0.id == existingID }),
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let asset = try? MediaStore.importPhoto(image, caption: "行情证据") else { return }
        asset.comparable = existing
        existing.evidenceAssetID = asset.id
        context.insert(asset)
        try? context.save()
        photoItem = nil
    }

    private func save() {
        guard let value = Double(price) else { errorMessage = "行情价格必须大于 0。"; return }
        let cents = kind == .sale ? Money.cents(fromWan: value) : Money.cents(fromYuan: value)
        if let message = BusinessRules.validateComparable(priceCents: cents, source: source, hasDate: true) {
            errorMessage = message
            return
        }
        let item = items.first { $0.id == existingID } ?? MarketComparable(priceCents: cents, sourceDescription: source)
        if existingID == nil { context.insert(item) }
        item.community = communities.first { $0.id == communityID }
        item.kind = kind
        item.dealDate = date
        item.priceCents = cents
        item.area = Double(area) ?? 0
        item.bedrooms = Int(bedrooms) ?? 0
        item.decoration = decoration
        item.floorDescription = floor
        item.sourceDescription = BusinessRules.trimmed(source)
        item.notes = notes
        item.updatedAt = Date()
        try? context.save()
        isDirty = false
        dismiss()
    }
}
