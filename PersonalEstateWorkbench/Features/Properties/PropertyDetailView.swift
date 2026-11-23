import SwiftData
import SwiftUI
import UIKit

struct PropertyDetailView: View {
    var propertyID: UUID
    @Query private var properties: [Property]
    @Query private var needs: [ClientNeed]
    @Query private var viewings: [Viewing]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var showEdit = false
    @State private var showStatus = false
    @State private var showPrice = false
    @State private var showFollow = false
    @State private var showDeal = false
    @State private var showArchive = false
    @State private var showDelete = false
    @State private var copied = false
    @State private var priceText = ""
    @State private var nextStatus: PropertyStatus = .available
    @State private var statusReason = ""
    @State private var errorMessage: String?
    @State private var showStatusReason = false

    private var property: Property? { properties.first { $0.id == propertyID } }

    var body: some View {
        Group {
            if let property {
                content(property)
            } else {
                EmptyStateView(title: "房源不在了", message: "可能已经删除。", systemImage: "house")
            }
        }
        .paperScreen()
        .navigationTitle("房源")
        .navigationBarTitleDisplayMode(.inline)
        .errorAlert($errorMessage)
    }

    @ViewBuilder
    private func content(_ property: Property) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PropertyMediaSection(property: property)
                VStack(alignment: .leading, spacing: 8) {
                    Text(Money.priceText(property.askingPriceCents, kind: property.listingKind))
                        .font(.title.weight(.bold))
                        .foregroundStyle(Theme.accent)
                    Text("\(property.communityName) \(property.doorText)")
                        .font(.title3.weight(.semibold))
                    HStack {
                        Badge(text: property.listingKind.title)
                        Badge(text: property.statusTitle, color: statusColor(property.status))
                        if property.isArchived { Badge(text: "已归档", color: Theme.muted) }
                    }
                    Text("\(property.layoutText) · \(property.areaText)")
                        .foregroundStyle(Theme.muted)
                    if !property.floorText.isEmpty || !property.orientation.isEmpty || !property.decoration.isEmpty {
                        Text([property.floorText, property.orientation, property.decoration].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                    }
                    TagWrap(tags: property.shareFeatures)
                    if let date = property.availableFrom {
                        InfoRow(title: "可入住", value: CNDate.day(date))
                    }
                    InfoRow(title: "看房方式", value: property.viewingMethod)
                    if let verified = property.lastVerifiedAt {
                        InfoRow(title: "上次核实", value: CNDate.day(verified))
                    }
                    if let materials = property.materialsVerifiedAt {
                        InfoRow(title: "资料核验", value: CNDate.day(materials))
                    }
                }
                .card()

                actionGrid(property)
                ownerCard(property)
                matchCard(property)
                followCard(property)
                historyCard(property)
                if !property.internalNotes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("内部备注").font(.headline)
                        Text("不进入对外分享").font(.caption).foregroundStyle(Theme.muted)
                        Text(property.internalNotes)
                    }
                    .card()
                }
            }
            .padding()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("编辑") { showEdit = true }
                    Button(property.isArchived ? "取消归档" : "归档") { showArchive = true }
                    Button("标记资料已核验") {
                        property.materialsVerifiedAt = Date()
                        property.updatedAt = Date()
                        try? context.save()
                    }
                    Button("删除", role: .destructive) { showDelete = true }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $showEdit) {
            NavigationStack {
                PropertyFormView(existingID: property.id, preset: nil, listingKind: property.listingKind, status: property.status)
            }
        }
        .sheet(isPresented: $showFollow) { NavigationStack { FollowUpFormView(propertyID: property.id, contactID: property.owner?.id) } }
        .sheet(isPresented: $showDeal) { NavigationStack { DealFormView(propertyID: property.id) } }
        .confirmationDialog("改状态", isPresented: $showStatus, titleVisibility: .visible) {
            ForEach(PropertyStatus.allCases) { status in
                Button(status.title(for: property.listingKind)) {
                    nextStatus = status
                    statusReason = ""
                    showStatusReason = true
                }
            }
        }
        .alert("状态变更原因", isPresented: $showStatusReason) {
            TextField("原因", text: $statusReason)
            Button("保存") { applyStatus(property) }
            Button("取消", role: .cancel) {}
        }
        .alert("改价", isPresented: $showPrice) {
            TextField(property.listingKind == .sale ? "万元" : "元/月", text: $priceText)
            Button("保存") {
                property.askingPriceCents = Money.parse(priceText, kind: property.listingKind) ?? 0
                property.updatedAt = Date()
                try? context.save()
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog(property.isArchived ? "取消归档？" : "归档这套房？", isPresented: $showArchive, titleVisibility: .visible) {
            Button(property.isArchived ? "取消归档" : "归档") {
                property.isArchived.toggle()
                property.updatedAt = Date()
                try? context.save()
            }
        } message: { Text("归档不会删除已关联的跟进和成交。") }
        .confirmationDialog("删除这套房？", isPresented: $showDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                for asset in property.mediaAssets { MediaStore.deleteFiles(for: asset) }
                context.delete(property)
                try? context.save()
                dismiss()
            }
        } message: { Text("应用内的照片和视频副本会一起删除，系统相册里的原件不动。") }
        .alert("已复制推荐文字", isPresented: $copied) { Button("好") {} }
    }

    private func actionGrid(_ property: Property) -> some View {
        VStack(spacing: 8) {
            HStack {
                action("改价") { priceText = ""; showPrice = true }
                action("改状态") { showStatus = true }
                action("写跟进") { showFollow = true }
            }
            HStack {
                action("登记成交") { showDeal = true }.disabled(!property.canRegisterDeal)
                action("复制推荐") {
                    UIPasteboard.general.string = ShareContentBuilder.recommendation(for: property)
                    copied = true
                }
                NavigationLink(value: RecordRoute.matchProperty(property.id)) {
                    Text("匹配客户").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func action(_ title: String, _ body: @escaping () -> Void) -> some View {
        Button(title, action: body).buttonStyle(.bordered).frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func ownerCard(_ property: Property) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("业主").font(.headline)
            if let owner = property.owner {
                Text(owner.displayName).font(.body.weight(.semibold))
                if !owner.phone.isEmpty {
                    Button("拨打 \(owner.phone)") { ContactActions.call(owner.phone) }
                }
                if !owner.wechat.isEmpty {
                    Button("复制微信并打开微信") { ContactActions.openWeChat(owner.wechat) }
                }
            } else {
                Text("还没有业主").foregroundStyle(Theme.muted)
            }
        }
        .card()
    }

    private func matchCard(_ property: Property) -> some View {
        let rows = MatchingService.needs(for: property, needs: needs.filter { $0.status == .active }, viewings: viewings)
        let qualified = rows.filter { $0.bucket == .qualified }
        let rejected = rows.filter { $0.bucket == .previouslyRejected }
        return VStack(alignment: .leading, spacing: 6) {
            Text("匹配客户").font(.headline)
            Text("符合已知条件 \(qualified.count) · 此前不考虑 \(rejected.count)")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
            NavigationLink("查看全部", value: RecordRoute.matchProperty(property.id))
        }
        .card()
    }

    private func followCard(_ property: Property) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("房源跟进").font(.headline)
            if property.followUps.isEmpty {
                Text("还没有跟进").foregroundStyle(Theme.muted)
            }
            ForEach(property.followUps.sorted { $0.occurredAt > $1.occurredAt }.prefix(5)) { follow in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(follow.channel.title) · \(CNDate.dayTime(follow.occurredAt))")
                        .font(.caption).foregroundStyle(Theme.muted)
                    Text(follow.content)
                }
            }
        }
        .card()
    }

    private func historyCard(_ property: Property) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("状态历史").font(.headline)
            ForEach(property.statusEvents.sorted { $0.occurredAt > $1.occurredAt }) { event in
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title(for: property.listingKind)).font(.subheadline.weight(.semibold))
                    Text("\(CNDate.dayTime(event.occurredAt)) · \(event.reason)")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
            }
        }
        .card()
    }

    private func applyStatus(_ property: Property) {
        if let message = BusinessRules.validateStatusChange(changed: nextStatus != property.status, reason: statusReason) {
            errorMessage = message
            return
        }
        PropertyService.recordStatusChange(of: property, to: nextStatus, reason: statusReason)
        try? context.save()
        try? WorkflowService.sync(context: context)
    }
}

enum ContactActions {
    static func call(_ phone: String) {
        let digits = BusinessRules.digits(phone)
        guard let url = URL(string: "tel://\(digits)"), !digits.isEmpty else { return }
        UIApplication.shared.open(url)
    }

    static func openWeChat(_ wechat: String) {
        UIPasteboard.general.string = wechat
        if let url = URL(string: "weixin://") {
            UIApplication.shared.open(url)
        }
    }
}
