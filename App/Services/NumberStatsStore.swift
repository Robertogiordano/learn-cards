import Foundation
import LearnCore

/// Number practice history, kept in UserDefaults (numbers are generated, not stored words)
/// and included in backups.
@MainActor
final class NumberStatsStore: ObservableObject {
    static let shared = NumberStatsStore()

    private static let key = "numberStats"

    @Published private(set) var stats: NumberStats

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let stored = try? JSONDecoder().decode(NumberStats.self, from: data) {
            stats = stored
        } else {
            stats = NumberStats()
        }
    }

    func record(_ correct: Bool, number: Int, level: NumberLevel, kind: NumberExerciseKind) {
        stats.record(correct, number: number, level: level, kind: kind)
        save()
    }

    func replaceLast(with correct: Bool, number: Int, level: NumberLevel, kind: NumberExerciseKind) {
        stats.replaceLast(with: correct, number: number, level: level, kind: kind)
        save()
    }

    /// From a backup.
    func replace(with stats: NumberStats) {
        self.stats = stats
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(stats) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
