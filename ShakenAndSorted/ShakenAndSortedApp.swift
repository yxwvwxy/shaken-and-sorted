import SwiftUI
import SwiftData

@main
struct ShakenAndSortedApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Cocktail.self, IngredientCategoryChoice.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        // Menu recognition is on device now; drop the old OpenAI key if one was saved.
        UserDefaults.standard.removeObject(forKey: "openai_api_key")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light)
        }
        .modelContainer(sharedModelContainer)
    }
}
