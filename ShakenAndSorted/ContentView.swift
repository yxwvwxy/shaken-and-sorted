import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        CocktailListView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Cocktail.self, inMemory: true)
}
