import Foundation
import LearnCore

/// Telling-the-time history, kept in UserDefaults (times are generated, not stored)
/// and included in backups.
@MainActor
final class TimeStatsStore: ObservableObject {
    static let shared = TimeStatsStore()

    private static let key = "timeStats"

    @Published private(set) var stats: TimeStats

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let stored = try? JSONDecoder().decode(TimeStats.self, from: data) {
            stats = stored
        } else {
            stats = TimeStats()
        }
    }

    func record(_ correct: Bool, time: ClockTime, level: TimeLevel, kind: TimeExerciseKind) {
        stats.record(correct, time: time, level: level, kind: kind)
        save()
    }

    func replaceLast(with correct: Bool, time: ClockTime, level: TimeLevel, kind: TimeExerciseKind) {
        stats.replaceLast(with: correct, time: time, level: level, kind: kind)
        save()
    }

    /// From a backup.
    func replace(with stats: TimeStats) {
        self.stats = stats
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(stats) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
