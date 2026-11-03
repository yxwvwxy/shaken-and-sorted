import SwiftUI
import SwiftData

/// Every ingredient from every logged drink, grouped by category, with the main
/// spirits split into subcategories.
struct IngredientsView: View {
    @Query(sort: \Cocktail.createdAt, order: .reverse) private var cocktails: [Cocktail]
    @Query private var choices: [IngredientCategoryChoice]
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            Group {
                if catalog.entries.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Ingredients")
            .navigationDestination(for: IngredientEntry.self) { entry in
                IngredientDetailView(entry: entry)
            }
        }
        .tint(AppTheme.accent)
    }

    private var catalog: IngredientCatalog {
        IngredientCatalog(cocktails: cocktails, choices: choices)
    }

    private var list: some View {
        List {
            ForEach(sections, id: \.category) { section in
                Section {
                    ForEach(section.groups, id: \.subcategory) { group in
                        if let subcategory = group.subcategory {
                            Text(subcategory.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.tertiaryText)
                                .listRowBackground(AppTheme.card)
                        }
                        ForEach(group.entries) { entry in
                            NavigationLink(value: entry) {
                                HStack {
                                    Text(entry.name)
                                        .foregroundStyle(AppTheme.primaryText)
                                    Spacer()
                                    Text("\(entry.cocktails.count)")
                                        .font(.subheadline)
                                        .foregroundStyle(AppTheme.tertiaryText)
                                }
                            }
                            .listRowBackground(AppTheme.card)
                        }
                    }
                } header: {
                    Text(section.category.title)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .searchable(text: $searchText, prompt: "Search ingredients")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("No ingredients yet")
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)
            Text("Ingredients from the drinks you log show up here, sorted by kind.")
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private struct SubcategoryGroup {
        var subcategory: IngredientSubcategory?
        var entries: [IngredientEntry]
    }

    private var sections: [(category: IngredientCategory, groups: [SubcategoryGroup])] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let shown = catalog.entries.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
        let byCategory = Dictionary(grouping: shown, by: \.kind.category)
        return IngredientCategory.allCases.compactMap { category in
            guard let items = byCategory[category], !items.isEmpty else { return nil }
            let alphabetical = items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            if category.subcategories.isEmpty {
                return (category, [SubcategoryGroup(subcategory: nil, entries: alphabetical)])
            }
            let bySubcategory = Dictionary(grouping: alphabetical) { $0.kind.subcategory }
            let groups = category.subcategories.compactMap { subcategory in
                bySubcategory[subcategory].map { SubcategoryGroup(subcategory: subcategory, entries: $0) }
            }
            return (category, groups)
        }
    }
}

/// One ingredient: its category (changeable) and the drinks it was in.
private struct IngredientDetailView: View {
    let entry: IngredientEntry
    @Environment(\.modelContext) private var modelContext
    @Environment(DrinkFilter.self) private var drinkFilter
    @Query private var choices: [IngredientCategoryChoice]
    @State private var kind = IngredientKind(category: .uncategorized)

    var body: some View {
        List {
            Section {
                Picker("Category", selection: $kind) {
                    ForEach(IngredientCategory.allCases) { category in
                        if category.subcategories.isEmpty {
                            Text(category.title).tag(IngredientKind(category: category))
                        } else {
                            Section(category.title) {
                                ForEach(category.subcategories) { subcategory in
                                    Text(subcategory.title)
                                        .tag(IngredientKind(category: category, subcategory: subcategory))
                                }
                            }
                        }
                    }
                }
                .pickerStyle(.menu)
            } footer: {
                Text("Sorted automatically from the name. Pick another category to fix it for every drink with this ingredient.")
            }
            .listRowBackground(AppTheme.card)

            Section {
                ForEach(entry.cocktails) { cocktail in
                    NavigationLink {
                        CocktailEditorView(mode: .edit(cocktail))
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cocktail.displayTitle)
                                .foregroundStyle(cocktail.hasName ? AppTheme.primaryText : AppTheme.tertiaryText)
                            Text(cocktail.createdAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(AppTheme.tertiaryText)
                        }
                    }
                }
                Button {
                    drinkFilter.showDrinks(with: entry)
                } label: {
                    Label("Show in Drinks", systemImage: "line.3.horizontal.decrease")
                }
            } header: {
                Text(entry.cocktails.count == 1 ? "In 1 drink" : "In \(entry.cocktails.count) drinks")
            }
            .listRowBackground(AppTheme.card)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle(entry.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { kind = entry.kind }
        .onChange(of: kind) { _, newValue in
            save(newValue)
        }
    }

    private func save(_ newValue: IngredientKind) {
        let existing = choices.first { $0.key == entry.key }
        if newValue == IngredientKind.guess(for: entry.name) {
            // Back to the automatic guess; no need to remember a choice.
            if let existing { modelContext.delete(existing) }
        } else if let existing {
            existing.kind = newValue
        } else if newValue != entry.kind {
            modelContext.insert(IngredientCategoryChoice(key: entry.key, kind: newValue))
        }
        try? modelContext.save()
    }
}
