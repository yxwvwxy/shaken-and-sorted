import SwiftUI
import SwiftData

struct ContentView: View {
    /// In memory only: the app always opens on every drink, newest first.
    @State private var drinkFilter = DrinkFilter()

    var body: some View {
        TabView(selection: $drinkFilter.selectedTab) {
            CocktailListView()
                .tabItem { Label("Drinks", systemImage: "list.bullet.rectangle") }
                .tag(AppTab.drinks)
            RecipesView()
                .tabItem { Label("Recipes", systemImage: "book") }
                .tag(AppTab.recipes)
            IngredientsView()
                .tabItem { Label("Ingredients", systemImage: "square.grid.2x2") }
                .tag(AppTab.ingredients)
        }
        .environment(drinkFilter)
        .tint(AppTheme.accent)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Cocktail.self, IngredientCategoryChoice.self], inMemory: true)
}
