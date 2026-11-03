import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        TabView {
            CocktailListView()
                .tabItem { Label("Drinks", systemImage: "list.bullet.rectangle") }
            IngredientsView()
                .tabItem { Label("Ingredients", systemImage: "square.grid.2x2") }
        }
        .tint(AppTheme.accent)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Cocktail.self, IngredientCategoryChoice.self], inMemory: true)
}
