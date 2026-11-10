import SwiftUI
import SwiftData

struct ContentView: View {
    /// In memory only: the app always opens on every drink, newest first.
    @State private var drinkFilter = DrinkFilter()

    var body: some View {
        TabView(selection: $drinkFilter.selectedTab) {
            RecipesView()
                .tabItem { Label("Recipes", systemImage: "book") }
                .tag(AppTab.recipes)
            CocktailListView()
                .tabItem { Label("Drinks", systemImage: "list.bullet.rectangle") }
                .tag(AppTab.drinks)
            IngredientsView()
                .tabItem { Label("Ingredients", systemImage: "square.grid.2x2") }
                .tag(AppTab.ingredients)
        }
        .environment(drinkFilter)
        .modifier(IngredientTranslationWatcher())
        .modifier(MadeCopyMerger())
        .tint(AppTheme.accent)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Cocktail.self, IngredientCategoryChoice.self, IngredientTranslation.self], inMemory: true)
}

/// Older versions logged a separate drink each time a recipe was marked made. A recipe
/// and its drink are one entry now, so each copy is folded into its recipe (filling only
/// what the recipe lacks; the newest copy's rating and date win) and then removed.
private struct MadeCopyMerger: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Cocktail> { $0.recipeID != nil }, sort: \Cocktail.createdAt, order: .reverse)
    private var copies: [Cocktail]
    @Query(filter: Cocktail.recipes) private var recipes: [Cocktail]

    func body(content: Content) -> some View {
        content.onChange(of: copies.count, initial: true) {
            merge()
        }
    }

    private func merge() {
        guard !copies.isEmpty else { return }
        let byID = Dictionary(recipes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for copy in copies {
            guard let recipeID = copy.recipeID, let recipe = byID[recipeID] else {
                copy.recipeID = nil
                continue
            }
            if recipe.isMade != true {
                recipe.isMade = true
                recipe.createdAt = copy.createdAt
                if copy.rating != nil { recipe.rating = copy.rating }
            } else if recipe.rating == nil {
                recipe.rating = copy.rating
            }
            if recipe.photos.isEmpty { recipe.photos = copy.photos }
            if (recipe.notes ?? "").isEmpty { recipe.notes = copy.notes }
            if !recipe.hasPlace, copy.hasPlace {
                recipe.placeName = copy.placeName
                recipe.placeAddress = copy.placeAddress
                recipe.latitude = copy.latitude
                recipe.longitude = copy.longitude
            }
            if recipe.price == nil { recipe.price = copy.price }
            modelContext.delete(copy)
        }
        try? modelContext.save()
    }
}
