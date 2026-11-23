import Foundation
import SwiftData

enum WorkflowService {
    static func sync(context: ModelContext) throws {
        let tasks = try context.all(TaskItem.self)
        let properties = try context.all(Property.self)
        let deals = try context.all(Deal.self)
        let viewings = try context.all(Viewing.self)
        let followUps = try context.all(FollowUp.self)

        var desired: [String: TaskSeed] = [:]
        for property in properties where !property.isArchived && property.status.needsReview {
            let key = "verification:\(property.id.uuidString)"
            desired[key] = TaskSeed(
                kind: .verification,
                title: "\(property.communityName) \(property.doorText)",
                notes: property.statusTitle,
                dueAt: Date(),
                sourceID: property.id
            )
        }
        for deal in deals where deal.status == .active && deal.kind == .rent {
            guard let end = deal.leaseEndOn else { continue }
            let key = "lease:\(deal.id.uuidString):\(CNDate.day(end))"
            let due = Calendar.current.date(byAdding: .day, value: -BusinessRules.leaseReminderDays, to: end) ?? end
            let place = deal.communityNameSnapshot.isEmpty ? "租约" : deal.communityNameSnapshot
            desired[key] = TaskSeed(kind: .lease, title: "\(place) 租约即将到期", notes: "提前 30 天提醒", dueAt: due, sourceID: deal.id)
        }
        for viewing in viewings where viewing.status == .scheduled {
            let key = "viewing:\(viewing.id.uuidString):\(Int(viewing.scheduledStart.timeIntervalSince1970))"
            let who = viewing.clientNeed?.contact?.displayName ?? "客户"
            desired[key] = TaskSeed(kind: .viewing, title: "带看 \(who)", notes: viewing.meetingPoint, dueAt: viewing.scheduledStart, sourceID: viewing.id)
        }
        for follow in followUps {
            guard let due = follow.nextDueAt else { continue }
            let key = "followup:\(follow.id.uuidString):\(Int(due.timeIntervalSince1970))"
            let who = follow.contact?.displayName ?? follow.clientNeed?.contact?.displayName ?? "客户"
            let note = follow.nextAction.isEmpty ? follow.content : follow.nextAction
            desired[key] = TaskSeed(kind: .followUp, title: "跟进 \(who)", notes: note, dueAt: due, sourceID: follow.id)
        }

        for (key, seed) in desired {
            if let existing = tasks.first(where: { $0.sourceKey == key }) {
                if existing.state == .open {
                    existing.title = seed.title
                    existing.notes = seed.notes
                    existing.dueAt = seed.dueAt
                    existing.updatedAt = Date()
                }
            } else {
                let task = TaskItem(
                    kind: seed.kind,
                    title: seed.title,
                    notes: seed.notes,
                    dueAt: seed.dueAt,
                    sourceID: seed.sourceID,
                    sourceKey: key
                )
                context.insert(task)
            }
        }

        for task in tasks where task.kind != .manual && task.state == .open && desired[task.sourceKey] == nil {
            task.state = .cancelled
            task.updatedAt = Date()
        }
        try context.save()
    }

    static func setState(_ task: TaskItem, state: TaskState) {
        task.state = state
        task.completedAt = state == .open ? nil : Date()
        task.updatedAt = Date()
    }

    static func cancelOpenTasks(sourceIDs: Set<UUID>, context: ModelContext) {
        guard let tasks = try? context.all(TaskItem.self) else { return }
        for task in tasks where task.state == .open {
            if let sourceID = task.sourceID, sourceIDs.contains(sourceID) {
                setState(task, state: .cancelled)
            }
        }
    }

    static func deleteContact(_ contact: Contact, context: ModelContext) {
        var sourceIDs: Set<UUID> = [contact.id]
        sourceIDs.formUnion(contact.followUps.map(\.id))
        sourceIDs.formUnion(contact.clientNeeds.map(\.id))
        cancelOpenTasks(sourceIDs: sourceIDs, context: context)
        if contact.isOwner {
            contact.roles = [.owner]
            for need in contact.clientNeeds where need.status != .closed {
                need.status = .closed
                if need.closedReason.isEmpty {
                    need.closedReason = "联系人仍保留为业主"
                }
                need.updatedAt = Date()
            }
            contact.updatedAt = Date()
        } else {
            context.delete(contact)
        }
    }

    static func appears(on day: Date, task: TaskItem, includeOverdue: Bool) -> Bool {
        guard task.state == .open else { return false }
        if CNDate.sameDay(task.dueAt, day) { return true }
        if includeOverdue && CNDate.startOfDay(task.dueAt) < CNDate.startOfDay(day) { return true }
        return false
    }
}

private struct TaskSeed {
    var kind: TaskKind
    var title: String
    var notes: String
    var dueAt: Date
    var sourceID: UUID?
}
