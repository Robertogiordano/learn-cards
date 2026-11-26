import LearnCore
import SwiftData
import SwiftUI

@main
struct LearnCardsApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [Word.self, Phrase.self, Verb.self])
    }
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context

    var body: some View {
        TabView {
            PathView()
                .tabItem { Label("Study", systemImage: "graduationcap") }
            GrammarView()
                .tabItem { Label("Grammar", systemImage: "pills") }
            VocabularyView()
                .tabItem { Label("Vocabulary", systemImage: "books.vertical") }
            ImportView()
                .tabItem { Label("Add", systemImage: "camera") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        // Reminders are planned a week ahead: refresh them whenever the app comes back.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { ReminderScheduler.reschedule() }
        }
        .task {
            renameLegacyDefaults()
            migrateSeparableVerbs()
        }
    }

    /// Separable used to be a group: make it a prefix of its own, read off the table, once.
    /// Verbs whose table does not show a prefix keep none until edited or filled with AI.
    private func migrateSeparableVerbs() {
        let key = "migratedSeparableVerbs"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let verbs = (try? context.fetch(FetchDescriptor<Verb>())) ?? []
        for verb in verbs where verb.separablePrefix == nil {
            verb.separablePrefix = SeparableVerbs.inferPrefix(infinitive: verb.infinitive, forms: verb.forms)
            if verb.group == .separable, verb.separablePrefix != nil { verb.group = .regular }
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: key)
    }

    /// The default theme and phrase category used to be Italian: rename them once.
    private func renameLegacyDefaults() {
        let key = "renamedLegacyDefaults"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let oldTheme = VocabEntry.legacyDefaultCategory
        let oldCategory = PhraseEntry.legacyDefaultCategory
        let words = (try? context.fetch(FetchDescriptor<Word>(predicate: #Predicate { $0.category == oldTheme }))) ?? []
        for word in words {
            word.category = VocabEntry.defaultCategory
        }
        let phrases = (try? context.fetch(FetchDescriptor<Phrase>(predicate: #Predicate { $0.category == oldCategory }))) ?? []
        for phrase in phrases {
            phrase.category = PhraseEntry.defaultCategory
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: key)
    }
}
