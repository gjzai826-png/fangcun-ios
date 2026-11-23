import Foundation
import SwiftData

@MainActor
enum DemoDataSeeder {
    static func seedIfNeeded(_ context: ModelContext) {
        let count = (try? context.all(Community.self).count) ?? 0
        if count == 0 {
            seed(context)
        }
    }

    static func ensureWorkspace(_ context: ModelContext, title: String) {
        let existing = (try? context.all(WorkspaceRecord.self)) ?? []
        if existing.isEmpty {
            context.insert(WorkspaceRecord(title: title))
            try? context.save()
        }
    }

    static func seed(_ context: ModelContext) {
        let calendar = Calendar.current
        let now = Date()
        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset, to: now) ?? now
        }

        let cuihu = Community(name: "翠湖花园", aliases: ["翠湖", "翠湖小区"], district: "西湖区", address: "文三路 88 号", notes: "南门好停车")
        let wangyue = Community(name: "望月公寓", aliases: ["望月"], district: "滨江区", address: "江南大道 200 号")
        let wenlan = Community(name: "文澜府", aliases: ["文澜"], district: "拱墅区", address: "湖墅北路 66 号")
        [cuihu, wangyue, wenlan].forEach(context.insert)

        let chen = Contact(displayName: "陈建国", phone: "13800001111", wechat: "chenjianguo", roles: [.owner], notes: "晚上方便联系")
        let zhou = Contact(displayName: "周海", phone: "13900002222", wechat: "zhouhai", roles: [.owner])
        let lin = Contact(displayName: "林晓婷", phone: "13700003333", wechat: "linxt", roles: [.buyer], notes: "转介绍，看学区")
        let zhao = Contact(displayName: "赵敏", phone: "13600004444", wechat: "zhaomin", roles: [.tenant])
        [chen, zhou, lin, zhao].forEach(context.insert)

        let sale = Property(
            building: "3", unit: "1", room: "1802", listingKind: .sale, status: .available,
            askingPriceCents: Money.cents(fromWan: 328), availableFrom: day(30), viewingMethod: "提前一天预约",
            bedrooms: 3, livingRooms: 1, bathrooms: 2, area: 89.6, floor: 18, totalFloors: 26,
            orientation: "南北", decoration: "精装", hasElevator: true,
            features: ["包物业", "包车位", "空调", "阳台"], internalNotes: "业主急售，不对外说底价。",
            lastVerifiedAt: day(-2)
        )
        sale.community = cuihu
        sale.owner = chen

        let rent = Property(
            building: "2", unit: "2", room: "906", listingKind: .rent, status: .available,
            askingPriceCents: Money.cents(fromYuan: 4500), viewingMethod: "周末可看",
            bedrooms: 2, livingRooms: 1, bathrooms: 1, area: 67, floor: 9, totalFloors: 18,
            orientation: "南", decoration: "简装", hasElevator: true,
            features: ["不包物业", "无车位", "冰箱"]
        )
        rent.community = wangyue
        rent.owner = zhou

        let review = Property(
            building: "1", unit: "1", room: "1501", listingKind: .sale, status: .needsVerification,
            askingPriceCents: Money.cents(fromWan: 560),
            bedrooms: 4, livingRooms: 2, bathrooms: 2, area: 143, floor: 15, totalFloors: 28,
            orientation: "南北", decoration: "豪装", hasElevator: true,
            features: ["包物业", "包车位"], internalNotes: "报价还没跟业主核对。"
        )
        review.community = wenlan
        review.owner = zhou

        let rented = Property(
            building: "5", unit: "1", room: "802", listingKind: .rent, status: .rented,
            askingPriceCents: Money.cents(fromYuan: 3800),
            bedrooms: 1, livingRooms: 1, bathrooms: 1, area: 48, floor: 8, totalFloors: 18,
            orientation: "东", decoration: "简装", hasElevator: true, features: ["不包物业", "无车位"]
        )
        rented.community = cuihu
        rented.owner = chen

        let offline = Property(
            building: "1", unit: "1", room: "303", listingKind: .sale, status: .offline,
            askingPriceCents: Money.cents(fromWan: 410),
            bedrooms: 3, livingRooms: 2, bathrooms: 2, area: 102, floor: 3, totalFloors: 11,
            orientation: "南", decoration: "精装", hasElevator: false, features: ["不包物业", "无车位"]
        )
        offline.community = wangyue
        offline.owner = zhou
        [sale, rent, review, rented, offline].forEach(context.insert)

        let buyNeed = ClientNeed(
            kind: .buy, status: .active, urgency: .urgent,
            budgetMinCents: Money.cents(fromWan: 300), budgetMaxCents: Money.cents(fromWan: 400),
            preferredDistricts: ["西湖区"], preferredCommunityIDs: [cuihu.id],
            bedroomsMin: 3, bedroomsMax: 3, areaMin: 80, areaMax: 120,
            mustHaveFeatures: [FeatureToken.elevator], preferencesNote: "希望南北通透", source: "转介绍"
        )
        buyNeed.contact = lin
        let rentNeed = ClientNeed(
            kind: .rent, status: .active, urgency: .soon,
            budgetMinCents: Money.cents(fromYuan: 3000), budgetMaxCents: Money.cents(fromYuan: 5000),
            preferredDistricts: ["滨江区"], bedroomsMin: 1, bedroomsMax: 2, areaMin: 40, areaMax: 80,
            excludedFeatures: [], preferencesNote: "离地铁近一些", source: "安居客", moveInDate: day(15)
        )
        rentNeed.contact = zhao
        context.insert(buyNeed)
        context.insert(rentNeed)

        let follow = FollowUp(
            channel: .call, content: "介绍了翠湖花园 1802，客户觉得总价还能谈。",
            outcome: "愿意周末再看", nextAction: "约带看", nextDueAt: now, occurredAt: day(-1)
        )
        follow.clientNeed = buyNeed
        follow.contact = lin
        follow.property = sale
        let ownerFollow = FollowUp(channel: .wechat, content: "跟陈先生确认了钥匙在物业。", occurredAt: day(-3))
        ownerFollow.property = sale
        ownerFollow.contact = chen
        context.insert(follow)
        context.insert(ownerFollow)

        let start = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: now) ?? now
        let end = calendar.date(bySettingHour: 15, minute: 0, second: 0, of: now) ?? now
        let viewing = Viewing(scheduledStart: start, scheduledEnd: end, meetingPoint: "翠湖花园南门", notes: "先看 1802")
        viewing.clientNeed = buyNeed
        let item = ViewingItem(sortOrder: 0)
        item.viewing = viewing
        item.property = sale
        context.insert(viewing)
        context.insert(item)

        let leaseStart = day(-340)
        let leaseEnd = day(20)
        let deal = Deal(
            kind: .rent, signedOn: leaseStart, actualPriceCents: Money.cents(fromYuan: 3800),
            commissionReceivableCents: Money.cents(fromYuan: 3800), commissionReceivedCents: Money.cents(fromYuan: 3800),
            leaseStartOn: leaseStart, leaseEndOn: leaseEnd, notes: "押一付三"
        )
        deal.property = rented
        deal.contact = zhao
        DealService.fillSnapshots(deal, property: rented, contact: zhao)
        context.insert(deal)
        let event = PropertyStatusEvent(reason: "登记成交", relatedDealID: deal.id, from: .available, to: .rented)
        event.property = rented
        context.insert(event)

        let comparable = MarketComparable(
            kind: .sale, dealDate: day(-12), priceCents: Money.cents(fromWan: 310), area: 86, bedrooms: 3,
            decoration: "精装", floorDescription: "中高层", sourceDescription: "安居客成交", notes: "同小区上一套成交，仅作参考。"
        )
        comparable.community = cuihu
        context.insert(comparable)

        context.insert(TaskItem(kind: .manual, title: "整理本周带看资料", notes: "打印户型图", dueAt: now, sourceKey: "manual:\(UUID().uuidString)"))
        context.insert(WorkspaceRecord(title: "演示数据"))
        try? context.save()
        try? WorkflowService.sync(context: context)
    }
}

@MainActor
enum PreviewStore {
    static let container: ModelContainer = {
        let configuration = ModelConfiguration(
            "preview",
            schema: EstateSchema.schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try! ModelContainer(for: EstateSchema.schema, configurations: [configuration])
        DemoDataSeeder.seed(container.mainContext)
        return container
    }()
}
