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

    var body: some View {
        TabView {
            PathView()
                .tabItem { Label("Studia", systemImage: "graduationcap") }
            VocabularyView()
                .tabItem { Label("Vocabolario", systemImage: "books.vertical") }
            ImportView()
                .tabItem { Label("Aggiungi", systemImage: "camera") }
            SettingsView()
                .tabItem { Label("Impostazioni", systemImage: "gearshape") }
        }
        // Reminders are planned a week ahead: refresh them whenever the app comes back.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { ReminderScheduler.reschedule() }
        }
    }
}
