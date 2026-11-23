import Foundation
import UserNotifications

enum NotificationPreferences {
    static let key = "notifications.enabled"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

@MainActor
enum LocalNotificationService {
    private static let prefix = "fangcun."

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static func reschedule(tasks: [TaskItem], deals: [Deal]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)
        guard NotificationPreferences.isEnabled else { return }

        var requests: [UNNotificationRequest] = []
        for task in tasks where task.state == .open && task.kind != .lease {
            guard let date = triggerDate(for: task), date > Date() else { continue }
            let content = UNMutableNotificationContent()
            content.title = "方寸"
            content.body = body(for: task)
            content.sound = .default
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            requests.append(UNNotificationRequest(identifier: prefix + task.id.uuidString, content: content, trigger: trigger))
        }
        for deal in deals where deal.status == .active && deal.kind == .rent {
            guard let end = deal.leaseEndOn else { continue }
            let before = Calendar.current.date(byAdding: .day, value: -BusinessRules.leaseReminderDays, to: end) ?? end
            requests.append(contentsOf: leaseRequests(dealID: deal.id, before: before, end: end))
        }
        for request in requests.prefix(40) {
            try? await center.add(request)
        }
    }

    private static func leaseRequests(dealID: UUID, before: Date, end: Date) -> [UNNotificationRequest] {
        var items: [UNNotificationRequest] = []
        for (suffix, day, body) in [
            ("before", atNine(before), "有一条租约将在 30 天内到期"),
            ("day", atNine(end), "有一条租约今天到期")
        ] where day > Date() {
            let content = UNMutableNotificationContent()
            content.title = "方寸"
            content.body = body
            content.sound = .default
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: day)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            items.append(UNNotificationRequest(identifier: prefix + "lease." + dealID.uuidString + "." + suffix, content: content, trigger: trigger))
        }
        return items
    }

    private static func body(for task: TaskItem) -> String {
        switch task.kind {
        case .verification: return "有房源待核实"
        case .lease: return "有一条租约需要留意"
        case .viewing: return "有一场带看"
        case .followUp: return "有一条待跟进"
        case .manual:
            return "有一条待办"
        }
    }

    private static func triggerDate(for task: TaskItem) -> Date? {
        switch task.kind {
        case .viewing, .followUp:
            return task.dueAt
        case .verification, .manual, .lease:
            return atNine(task.dueAt)
        }
    }

    private static func atNine(_ date: Date) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        components.hour = 9
        components.minute = 0
        return Calendar.current.date(from: components) ?? date
    }
}
