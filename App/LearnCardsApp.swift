import SwiftData
import SwiftUI

@main
struct LearnCardsApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: Word.self)
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            StudyHomeView()
                .tabItem { Label("Studia", systemImage: "graduationcap") }
            VocabularyView()
                .tabItem { Label("Vocabolario", systemImage: "books.vertical") }
            ImportView()
                .tabItem { Label("Aggiungi", systemImage: "camera") }
            SettingsView()
                .tabItem { Label("Impostazioni", systemImage: "gearshape") }
        }
    }
}
