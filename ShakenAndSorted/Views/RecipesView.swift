import SwiftUI
import SwiftData

/// Drinks you want to make. Each shows whether and how often you've made it.
struct RecipesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: Cocktail.recipes, sort: \Cocktail.createdAt, order: .reverse) private var recipes: [Cocktail]
    @Query(filter: Cocktail.loggedDrinks, sort: \Cocktail.createdAt, order: .reverse) private var drinks: [Cocktail]
    @State private var showingAdd = false
    @State private var show: RecipeFilter = .all

    var body: some View {
        NavigationStack {
            Group {
                if recipes.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Recipes")
            .navigationDestination(for: Cocktail.self) { recipe in
                CocktailEditorView(mode: .edit(recipe))
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }
                    .accessibilityLabel("Add recipe")
                }
            }
            .sheet(isPresented: $showingAdd) {
                CocktailEditorView(mode: .addRecipe)
            }
        }
        .tint(AppTheme.accent)
    }

    /// Logged drinks per recipe, newest first.
    private var madeByRecipe: [UUID: [Cocktail]] {
        Dictionary(grouping: drinks.filter { $0.recipeID != nil }, by: { $0.recipeID! })
    }

    private var list: some View {
        let made = madeByRecipe
        let shown = recipes.filter { recipe in
            switch show {
            case .all: return true
            case .toMake: return made[recipe.id] == nil
            case .made: return made[recipe.id] != nil
            }
        }
        return List {
            Picker("Show", selection: $show) {
                ForEach(RecipeFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            ForEach(shown) { recipe in
                NavigationLink(value: recipe) {
                    RecipeRow(recipe: recipe, made: made[recipe.id] ?? [])
                }
                .listRowBackground(AppTheme.card)
            }
            .onDelete { offsets in
                for index in offsets {
                    modelContext.delete(shown[index])
                }
                try? modelContext.save()
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if shown.isEmpty {
                Text(show == .toMake ? "You've made them all." : "Nothing made yet.")
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "book")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(AppTheme.accent)
            Text("No recipes yet")
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)
            Text("Save drinks you want to make, with amounts and a link to the post you found them in.")
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                showingAdd = true
            } label: {
                Text("Add a recipe")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 48)
            .padding(.top, 8)
            Spacer()
        }
    }
}

private enum RecipeFilter: CaseIterable, Identifiable {
    case all, toMake, made

    var id: Self { self }

    var title: String {
        switch self {
        case .all: return "All"
        case .toMake: return "To Make"
        case .made: return "Made"
        }
    }
}

private struct RecipeRow: View {
    let recipe: Cocktail
    let made: [Cocktail]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(recipe.displayTitle)
                    .font(.headline)
                    .foregroundStyle(recipe.hasName ? AppTheme.primaryText : AppTheme.tertiaryText)
                Spacer(minLength: 0)
                madeBadge
            }

            if !recipe.ingredientLines.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(recipe.ingredientLines.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("•")
                            Text(line.amount.isEmpty ? line.name : "\(line.amount) \(line.name)")
                        }
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                    }
                }
            }

            if recipe.sourceURL != nil {
                Label("Has source link", systemImage: "link")
                    .font(.caption)
                    .foregroundStyle(AppTheme.tertiaryText)
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var madeBadge: some View {
        if let last = made.first {
            Text(made.count == 1 ? "Made · \(last.createdAt.formatted(.dateTime.month(.abbreviated).day()))"
                 : "Made \(made.count)× · \(last.createdAt.formatted(.dateTime.month(.abbreviated).day()))")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(DrinkRating.loveIt.color, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
}
