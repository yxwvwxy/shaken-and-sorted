import SwiftUI
import SwiftData

struct CocktailListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(DrinkFilter.self) private var filter
    @Query(filter: Cocktail.loggedDrinks, sort: \Cocktail.createdAt, order: .reverse) private var cocktails: [Cocktail]
    @Query private var choices: [IngredientCategoryChoice]
    @State private var showingAdd = false
    @State private var showingSettings = false
    @State private var showingFilters = false

    private var catalog: IngredientCatalog {
        IngredientCatalog(cocktails: cocktails, choices: choices)
    }

    var body: some View {
        @Bindable var filter = filter
        NavigationStack(path: $filter.drinksPath) {
            Group {
                if cocktails.isEmpty {
                    emptyState
                } else {
                    listContent
                        .searchable(
                            text: $filter.searchText,
                            tokens: $filter.tokens,
                            placement: .navigationBarDrawer(displayMode: .always),
                            prompt: "Search drinks, ingredients, places"
                        ) { token in
                            Label { Text(token.label) } icon: { tokenIcon(token) }
                        }
                        .searchSuggestions { suggestions }
                }
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Shaken & Sorted")
            .navigationDestination(for: Cocktail.self) { cocktail in
                CocktailEditorView(mode: .edit(cocktail))
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingFilters = true
                    } label: {
                        Image(systemName: filter.hasSheetSettings
                              ? "line.3.horizontal.decrease.circle.fill"
                              : "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Filter and sort")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }
                    .accessibilityLabel("Add cocktail")
                }
            }
            .sheet(isPresented: $showingAdd) {
                CocktailEditorView(mode: .add)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingFilters) {
                DrinkFilterSheet()
                    .presentationDetents([.medium, .large])
            }
        }
        .tint(AppTheme.accent)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            MartiniGlass()
                .stroke(AppTheme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: 44, height: 52)
            Text("No drinks yet")
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)
            Text("Log what you drank and what was in it.")
                .font(.body)
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                showingAdd = true
            } label: {
                Text("Add your first")
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

    private var shownCocktails: [Cocktail] {
        filter.apply(to: cocktails, catalog: catalog)
    }

    private var listContent: some View {
        let shown = shownCocktails
        return List {
            ForEach(shown) { cocktail in
                NavigationLink(value: cocktail) {
                    CocktailRowView(cocktail: cocktail)
                }
                .listRowBackground(AppTheme.card)
            }
            .onDelete { offsets in
                delete(offsets, from: shown)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            if filter.isFiltering {
                filterSummary(count: shown.count)
            }
        }
        .overlay {
            if shown.isEmpty, filter.isFiltering {
                VStack(spacing: 12) {
                    Text("No drinks match")
                        .font(.headline)
                        .foregroundStyle(AppTheme.primaryText)
                    Button("Clear all") { filter.clearFilters() }
                }
            }
        }
    }

    /// The filter-sheet conditions as removable chips, the match count, and Clear all.
    private func filterSummary(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            let chips = activeChips
            if !chips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(chips, id: \.title) { chip in
                            Button(action: chip.remove) {
                                HStack(spacing: 4) {
                                    Text(chip.title)
                                    Image(systemName: "xmark")
                                        .font(.caption2.weight(.bold))
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.primaryText)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(chip.color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            HStack {
                Text("Showing \(count) of \(cocktails.count)")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                Spacer()
                Button("Clear all") { filter.clearFilters() }
                    .font(.caption.weight(.semibold))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(AppTheme.background)
    }

    private struct Chip {
        var title: String
        var color: Color
        var remove: () -> Void
    }

    private var activeChips: [Chip] {
        var chips: [Chip] = RatingOption.allCases.filter(filter.ratings.contains).map { option in
            Chip(title: option.title, color: option.rating?.color ?? AppTheme.photoPlaceholder) {
                filter.ratings.remove(option)
            }
        }
        if filter.dateRange != .allTime {
            chips.append(Chip(title: filter.dateRange.title, color: AppTheme.photoPlaceholder) {
                filter.dateRange = .allTime
            })
        }
        return chips
    }

    /// Grouped suggestions for what's typed: categories, ingredients, drinks and places
    /// that exist in the log. Picking one turns it into a token in the search field.
    @ViewBuilder
    private var suggestions: some View {
        let query = filter.searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            let catalog = catalog
            let kinds = kindSuggestions(for: query, catalog: catalog)
            let ingredients = catalog.entries
                .filter { $0.name.localizedCaseInsensitiveContains(query) }
                .map { DrinkFilterToken.ingredient(key: $0.key, name: $0.name) }
                .filter { !filter.tokens.contains($0) }
                .prefix(8)
            let drinks = Array(Set(cocktails.filter { $0.hasName && $0.trimmedName.localizedCaseInsensitiveContains(query) }
                .map(\.trimmedName))).sorted()
                .map(DrinkFilterToken.drink)
                .filter { !filter.tokens.contains($0) }
                .prefix(5)
            let places = Array(Set(cocktails.compactMap(\.placeName).filter { $0.localizedCaseInsensitiveContains(query) }))
                .sorted()
                .map(DrinkFilterToken.place)
                .filter { !filter.tokens.contains($0) }
                .prefix(5)

            suggestionSection("Categories", kinds)
            suggestionSection("Ingredients", Array(ingredients))
            suggestionSection("Drinks", Array(drinks))
            suggestionSection("Places", Array(places))
        }
    }

    @ViewBuilder
    private func suggestionSection(_ title: String, _ tokens: [DrinkFilterToken]) -> some View {
        if !tokens.isEmpty {
            Section(title) {
                ForEach(tokens) { token in
                    Label { Text(suggestionTitle(token)) } icon: { tokenIcon(token) }
                        .searchCompletion(token)
                }
            }
        }
    }

    /// Drinks get the same martini glass as the empty list; the rest use SF Symbols.
    private func tokenIcon(_ token: DrinkFilterToken) -> Image {
        if case .drink = token {
            return Image(uiImage: MartiniGlass.icon)
        }
        return Image(systemName: token.systemImage)
    }

    /// Subcategories say which category they're in ("Rye · Whiskey").
    private func suggestionTitle(_ token: DrinkFilterToken) -> String {
        if case .kind(let kind) = token, kind.subcategory != nil {
            return "\(kind.title) · \(kind.category.title)"
        }
        return token.label
    }

    /// Categories and subcategories the typed text names, by title ("rye", "whis") or by
    /// how an ingredient with that name would be filed ("whisky", "bourbon"), limited to
    /// kinds that actually appear in the log.
    private func kindSuggestions(for query: String, catalog: IngredientCatalog) -> [DrinkFilterToken] {
        let present = Set(catalog.entries.map(\.kind))
        let presentCategories = Set(present.map(\.category))
        let guessed = IngredientKind.guess(for: query)

        var kinds: [IngredientKind] = []
        for category in IngredientCategory.allCases where category != .uncategorized && presentCategories.contains(category) {
            let whole = IngredientKind(category: category)
            if category.title.localizedCaseInsensitiveContains(query) || guessed.category == category {
                kinds.append(whole)
            }
            for subcategory in category.subcategories {
                let kind = IngredientKind(category: category, subcategory: subcategory)
                guard present.contains(kind) else { continue }
                if subcategory.title.localizedCaseInsensitiveContains(query) || guessed == kind {
                    kinds.append(kind)
                }
            }
        }
        return kinds.map(DrinkFilterToken.kind).filter { !filter.tokens.contains($0) }
    }

    private func delete(_ offsets: IndexSet, from shown: [Cocktail]) {
        for index in offsets {
            modelContext.delete(shown[index])
        }
        try? modelContext.save()
    }
}

/// Sort order, rating and date filters for the Drinks list.
private struct DrinkFilterSheet: View {
    @Environment(DrinkFilter.self) private var filter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var filter = filter
        NavigationStack {
            Form {
                Section("Sort By") {
                    Picker("Sort By", selection: $filter.sort) {
                        ForEach(DrinkSortOrder.allCases) { order in
                            Text(order.title).tag(order)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                        ForEach(RatingOption.allCases) { option in
                            let selected = filter.ratings.contains(option)
                            Button {
                                if selected {
                                    filter.ratings.remove(option)
                                } else {
                                    filter.ratings.insert(option)
                                }
                            } label: {
                                Text(option.title)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9)
                                    .foregroundStyle(AppTheme.primaryText)
                                    .background(
                                        selected ? (option.rating?.color ?? Color(white: 0.85)) : AppTheme.card,
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    )
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(
                                                selected ? AppTheme.primaryText.opacity(0.5) : AppTheme.tertiaryText.opacity(0.4),
                                                lineWidth: selected ? 1.5 : 1
                                            )
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Rating")
                } footer: {
                    Text("Pick any to show only those. None picked shows all.")
                }

                Section("Date") {
                    Picker("Date", selection: $filter.dateRange) {
                        ForEach(DateRange.allCases) { range in
                            Text(range.title).tag(range)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Filter & Sort")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") { filter.resetSheet() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .tint(AppTheme.accent)
    }
}

private struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(MapApp.storageKey) private var defaultApp: MapApp = .ask

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Open Places In", selection: $defaultApp) {
                        ForEach(MapApp.allCases) { app in
                            Text(app.title).tag(app)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Open Places In")
                } footer: {
                    Text("Tapping a drink's place opens this map. Long-press the place to pick another one.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(AppTheme.accent)
    }
}

/// Martini (cocktail) glass outline — SF Symbols has no cocktail glass.
private struct MartiniGlass: Shape {
    /// The glass at symbol size, for places that only take an image (search tokens and
    /// suggestions). Same proportions and round strokes as the empty-list glass; tinted like a symbol.
    static let icon: UIImage = {
        let size = CGSize(width: 15, height: 18)
        let lineWidth: CGFloat = 1.5
        let rect = CGRect(origin: .zero, size: size).insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let path = MartiniGlass().path(in: rect).cgPath
            context.cgContext.addPath(path)
            context.cgContext.setLineWidth(lineWidth)
            context.cgContext.setLineCap(.round)
            context.cgContext.setLineJoin(.round)
            context.cgContext.setStrokeColor(UIColor.black.cgColor)
            context.cgContext.strokePath()
        }
        return image.withRenderingMode(.alwaysTemplate)
    }()

    func path(in rect: CGRect) -> Path {
        let bowlBottom = rect.minY + rect.height * 0.48
        var path = Path()
        // Bowl
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: bowlBottom))
        path.closeSubpath()
        // Stem
        path.move(to: CGPoint(x: rect.midX, y: bowlBottom))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        // Foot
        path.move(to: CGPoint(x: rect.midX - rect.width * 0.3, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.3, y: rect.maxY))
        return path
    }
}
