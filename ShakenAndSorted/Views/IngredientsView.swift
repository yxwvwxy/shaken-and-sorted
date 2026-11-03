import SwiftUI
import SwiftData

/// Every ingredient from every logged drink, grouped by category.
struct IngredientsView: View {
    @Query(sort: \Cocktail.createdAt, order: .reverse) private var cocktails: [Cocktail]
    @Query private var choices: [IngredientCategoryChoice]
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
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

    private var list: some View {
        List {
            ForEach(sections, id: \.category) { section in
                Section {
                    ForEach(section.entries) { entry in
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

    /// Ingredients merged across drinks by their normalized spelling.
    private var entries: [IngredientEntry] {
        let picked = Dictionary(choices.map { ($0.key, $0.category) }, uniquingKeysWith: { first, _ in first })
        var byKey: [String: IngredientEntry] = [:]
        for cocktail in cocktails {
            for name in cocktail.cleanedIngredients {
                let key = IngredientKey.normalized(name)
                if byKey[key] == nil {
                    byKey[key] = IngredientEntry(
                        key: key,
                        name: name,
                        category: picked[key] ?? IngredientCategory.guess(for: name),
                        cocktails: []
                    )
                }
                if byKey[key]?.cocktails.contains(where: { $0.id == cocktail.id }) == false {
                    byKey[key]?.cocktails.append(cocktail)
                }
            }
        }
        return Array(byKey.values)
    }

    private var sections: [(category: IngredientCategory, entries: [IngredientEntry])] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let shown = entries.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
        let grouped = Dictionary(grouping: shown, by: \.category)
        return IngredientCategory.allCases.compactMap { category in
            guard let items = grouped[category], !items.isEmpty else { return nil }
            return (category, items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        }
    }
}

struct IngredientEntry: Identifiable, Hashable {
    let key: String
    /// Spelling from the most recent drink that has it.
    let name: String
    let category: IngredientCategory
    var cocktails: [Cocktail]

    var id: String { key }

    static func == (lhs: IngredientEntry, rhs: IngredientEntry) -> Bool { lhs.key == rhs.key }
    func hash(into hasher: inout Hasher) { hasher.combine(key) }
}

/// One ingredient: its category (changeable) and the drinks it was in.
private struct IngredientDetailView: View {
    let entry: IngredientEntry
    @Environment(\.modelContext) private var modelContext
    @Query private var choices: [IngredientCategoryChoice]
    @State private var category: IngredientCategory = .uncategorized

    var body: some View {
        List {
            Section {
                Picker("Category", selection: $category) {
                    ForEach(IngredientCategory.allCases) { category in
                        Text(category.title).tag(category)
                    }
                }
                .pickerStyle(.menu)
            } footer: {
                Text("Sorted automatically from the name. Pick another category to fix it for every drink with this ingredient.")
            }
            .listRowBackground(AppTheme.card)

            Section(entry.cocktails.count == 1 ? "In 1 drink" : "In \(entry.cocktails.count) drinks") {
                ForEach(entry.cocktails) { cocktail in
                    NavigationLink {
                        CocktailDetailView(cocktail: cocktail)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cocktail.displayTitle)
                                .foregroundStyle(AppTheme.primaryText)
                            Text(cocktail.createdAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(AppTheme.tertiaryText)
                        }
                    }
                }
            }
            .listRowBackground(AppTheme.card)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle(entry.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { category = entry.category }
        .onChange(of: category) { _, newValue in
            save(newValue)
        }
    }

    private func save(_ newValue: IngredientCategory) {
        let existing = choices.first { $0.key == entry.key }
        if newValue == IngredientCategory.guess(for: entry.name) {
            // Back to the automatic guess; no need to remember a choice.
            if let existing { modelContext.delete(existing) }
        } else if let existing {
            existing.category = newValue
        } else if newValue != entry.category {
            modelContext.insert(IngredientCategoryChoice(key: entry.key, category: newValue))
        }
    }
}
