import Foundation
import LearnCore
import UserNotifications

/// Daily active time and recent mistakes, kept in UserDefaults and included in backups.
@MainActor
final class ActivityStore: ObservableObject {
    static let shared = ActivityStore()

    private static let key = "activityStats"

    @Published private(set) var stats: ActivityStats

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let stored = try? JSONDecoder().decode(ActivityStats.self, from: data) {
            stats = stored
        } else {
            stats = ActivityStats()
        }
    }

    var goalMinutes: Int { UserDefaults.standard.integer(forKey: SettingsKey.dailyGoalMinutes) }

    var secondsToday: Int { stats.seconds(on: .now) }

    var isGoalReachedToday: Bool { goalMinutes > 0 && secondsToday >= goalMinutes * 60 }

    func addActive(seconds: TimeInterval) {
        let wasReached = isGoalReachedToday
        stats.add(seconds: Int(seconds.rounded()), on: .now)
        save()
        // Once today's goal is reached, today's reminder is no longer needed.
        if !wasReached && isGoalReachedToday {
            ReminderScheduler.reschedule()
        }
    }

    func log(_ error: ErrorRecord) {
        stats.log(error)
        save()
    }

    /// Takes back the last mistake when the learner says the answer was right.
    func removeLastError(itemID: UUID?, exercise: String) {
        guard let last = stats.errors.last, last.itemID == itemID, last.exercise == exercise else { return }
        stats.errors.removeLast()
        save()
    }

    func replace(with stats: ActivityStats) {
        self.stats = stats
        save()
    }

    /// Keeps the longer time of each day and the mistakes of both, in order.
    func merge(_ other: ActivityStats) {
        var merged = stats
        for (day, seconds) in other.secondsByDay {
            merged.secondsByDay[day] = max(merged.secondsByDay[day] ?? 0, seconds)
        }
        let known = Set(merged.errors.map { "\($0.date.timeIntervalSince1970)|\($0.prompt)" })
        for error in other.errors where !known.contains("\(error.date.timeIntervalSince1970)|\(error.prompt)") {
            merged.errors.append(error)
        }
        merged.errors.sort { $0.date < $1.date }
        if merged.errors.count > ActivityStats.maximumErrors {
            merged.errors.removeFirst(merged.errors.count - ActivityStats.maximumErrors)
        }
        replace(with: merged)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(stats) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

/// Local daily reminders: one notification per day for the next week, skipping today
/// when the goal is already reached.
@MainActor
enum ReminderScheduler {
    private static let prefix = "learncards.reminder."

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func reschedule() {
        let center = UNUserNotificationCenter.current()
        let defaults = UserDefaults.standard
        // The app schedules nothing else, so clearing everything keeps the order of operations simple.
        center.removeAllPendingNotificationRequests()
        guard defaults.bool(forKey: SettingsKey.reminderEnabled) else { return }

        let minutes = defaults.object(forKey: SettingsKey.reminderMinutes) as? Int ?? 18 * 60
        let goal = defaults.integer(forKey: SettingsKey.dailyGoalMinutes)
        let calendar = Calendar.current
        let now = Date()
        let skipToday = ActivityStore.shared.isGoalReachedToday

        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)),
                  let fire = calendar.date(byAdding: .minute, value: minutes, to: day),
                  fire > now, !(offset == 0 && skipToday) else { continue }
            let content = UNMutableNotificationContent()
            content.title = "Time for German 🇩🇪"
            content.body = goal > 0
                ? "Just a few minutes to today's goal (\(goal) min). Today's lesson is waiting."
                : "Today's lesson is waiting."
            content.sound = .default
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            center.add(UNNotificationRequest(identifier: prefix + ActivityStats.dayKey(day), content: content, trigger: trigger))
        }
    }
}
