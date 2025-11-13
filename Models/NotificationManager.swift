import Foundation
import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        } catch { return false }
    }

    func scheduleForItem(_ item: Item, user: User) {
        // Skip scheduling for items already expired (compare by local calendar day)
        if let expiredUTC = SharedProperties.parseStringToDate(from: item.expiredDate, to: "yyyy-MM-dd") {
            var utcCal = Calendar(identifier: .gregorian)
            utcCal.timeZone = TimeZone(secondsFromGMT: 0)!
            let comps = utcCal.dateComponents([.year, .month, .day], from: expiredUTC)
            var localCal = Calendar.current
            localCal.timeZone = TimeZone.current
            let expiredLocal = localCal.date(from: DateComponents(year: comps.year, month: comps.month, day: comps.day, hour: 12)) ?? expiredUTC
            let todayLocal = localCal.date(from: localCal.dateComponents([.year, .month, .day], from: Date())) ?? Date()
            if expiredLocal < todayLocal { return }
        }
        
        guard var fire = Self.alertDate(forExpiredISO: item.expiredDate, alertDay: user.alert_day, alertTime: user.alert_time) else { return }
        let now = Date()
        // If the computed time is already passed (or within a few seconds), push it out ~1 minute
        if fire <= now.addingTimeInterval(5) {
            fire = now.addingTimeInterval(65)
        }

        let id = "expiry_item_\(item.itemCode)"
        let content = UNMutableNotificationContent()
        content.title = "Expiring soon"
        content.body = "\(item.itemName.capitalized) expires on \(item.expiredDate)"
        content.sound = .default

        let comps = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute], from: fire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.add(request)
    }

    func cancelForItemCode(_ code: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["expiry_item_\(code)"])
    }

    func rescheduleAll(items: [Item], user: User) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { reqs in
            let mine = reqs.map(\.identifier).filter { $0.hasPrefix("expiry_item_") }
            center.removePendingNotificationRequests(withIdentifiers: mine)
            DispatchQueue.main.async {
                items.forEach { self.scheduleForItem($0, user: user) }
            }
        }
    }

    static func alertDate(forExpiredISO iso: String, alertDay: Int, alertTime: String) -> Date? {
        guard let expired = SharedProperties.parseStringToDate(from: iso, to: "yyyy-MM-dd") else { return nil }
        var cal = Calendar.current; cal.timeZone = .current
        guard let pre = cal.date(byAdding: .day, value: -alertDay, to: expired) else { return nil }
        let parts = alertTime.split(separator: ":")
        let h = Int(parts.first ?? "8") ?? 8
        let m = Int(parts.dropFirst().first ?? "0") ?? 0
        var comps = cal.dateComponents([.year,.month,.day], from: pre)
        comps.hour = h; comps.minute = m
        return cal.date(from: comps)
    }
}


