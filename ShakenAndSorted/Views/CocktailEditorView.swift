import SwiftUI
import SwiftData

enum CocktailEditorMode {
    case add
    case addRecipe
    case edit(Cocktail)
}

/// Adding a drink or recipe (a sheet with Cancel / Save), or a saved one's own page,
/// which is editable right away and saves as you go. Recipes skip rating, price,
/// date and place, and get a source link and Mark as Made.
struct CocktailEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(DrinkFilter.self) private var drinkFilter
    @Query(filter: Cocktail.loggedDrinks, sort: \Cocktail.createdAt, order: .reverse) private var loggedDrinks: [Cocktail]

    let mode: CocktailEditorMode

    @State private var name: String = ""
    @State private var ingredients: [IngredientRow] = [IngredientRow()]
    @State private var photos: [Data] = []
    @State private var placeName: String?
    @State private var placeAddress: String?
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var price = ""
    @State private var date = Date.now
    @State private var rating: DrinkRating?
    @State private var sourceURL = ""
    @State private var notes = ""
    @State private var amountDisplay: AmountDisplay = .asWritten
    @State private var showingPlaceSearch = false
    @State private var showingMenuScan = false
    @State private var showingValidationAlert = false
    @State private var showingDeleteConfirm = false
    @State private var hasLoaded = false
    /// The page as it was when opened, for Undo.
    @State private var original: EditorSnapshot?
    @State private var showingUndoConfirm = false
    @State private var isDeleted = false
    @FocusState private var focus: IngredientField?

    private var canSave: Bool {
        // For a recipe the source link stands in for the place.
        Cocktail.canSave(
            name: name, ingredients: ingredients.map(\.text), photoData: photos.first,
            placeName: isRecipe ? trimmedSourceURL : placeName
        )
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var isRecipe: Bool {
        switch mode {
        case .add: return false
        case .addRecipe: return true
        case .edit(let cocktail): return cocktail.isRecipeEntry
        }
    }

    private var trimmedSourceURL: String? {
        let trimmed = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Drinks logged from this recipe, newest first.
    private var madeDrinks: [Cocktail] {
        guard case .edit(let cocktail) = mode, cocktail.isRecipeEntry else { return [] }
        return loggedDrinks.filter { $0.recipeID == cocktail.id }
    }

    var body: some View {
        switch mode {
        case .add, .addRecipe:
            NavigationStack { form }
                .tint(AppTheme.accent)
        case .edit:
            // Pushed onto the list's navigation stack, so no stack of its own.
            form
        }
    }

    private var form: some View {
        Form {
            if isRecipe, isEditing {
                markAsMadeSection
            }

            Section {
                Button {
                    showingMenuScan = true
                } label: {
                    Label(isRecipe ? "Scan a recipe" : "Scan from menu", systemImage: "menucard")
                }
            } footer: {
                Text(isRecipe
                     ? "Photo a recipe card or a screenshot, highlight the name and ingredients."
                     : "Photo a menu, highlight one drink, then edit anything before saving.")
            }

            Section("Name") {
                TextField("Cocktail name", text: $name, axis: .vertical)
                    .textInputAutocapitalization(.words)
            }

            ingredientsSection

            if isRecipe {
                sourceSection
            } else {
                loggedOnlySections
            }

            Section("Notes") {
                TextField(isRecipe ? "Method, tips, what to try next time" : "How it tasted, who made it, anything to remember",
                          text: $notes, axis: .vertical)
                    .lineLimit(3...)
            }

            Section("Photo") {
                PhotoPickerField(photos: $photos)
            }

            if isEditing {
                deleteSection
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        // A logged drink gets its own Back so leaving with nothing to save can be stopped.
        .navigationBarBackButtonHidden(isEditing)
        .toolbar {
            if isEditing {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if canSave {
                            dismiss()
                        } else {
                            showingValidationAlert = true
                        }
                    } label: {
                        Image(systemName: "chevron.backward")
                            .fontWeight(.semibold)
                    }
                    .accessibilityLabel("Back")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingUndoConfirm = true
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(original == nil || original == snapshot)
                    .accessibilityLabel("Undo changes")
                    .confirmationDialog("Undo your changes?", isPresented: $showingUndoConfirm, titleVisibility: .visible) {
                        Button("Undo Changes", role: .destructive, action: undoChanges)
                    } message: {
                        Text("Everything goes back to how it was when you opened this page.")
                    }
                }
            } else {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
            ToolbarItem(placement: .keyboard) {
                if case .amount(let id) = focus {
                    unitButtons(for: id)
                }
            }
        }
        .alert("Nothing to save yet", isPresented: $showingValidationAlert) {
            if isEditing {
                Button("Keep Editing", role: .cancel) {}
                Button("Discard Changes", role: .destructive) {
                    // Edits only reach the drink once one of the four is filled, so it still has what it had.
                    dismiss()
                }
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: {
            Text(isRecipe
                 ? "Add at least one of these: a name, an ingredient, a link, or a photo."
                 : "Add at least one of these: a name, an ingredient, a place, or a photo.")
        }
        .sheet(isPresented: $showingPlaceSearch) {
            PlaceSearchView(
                placeName: $placeName,
                placeAddress: $placeAddress,
                latitude: $latitude,
                longitude: $longitude
            )
        }
        .fullScreenCover(isPresented: $showingMenuScan) {
            MenuScanView { result in
                applyScan(result)
            }
        }
        .onAppear(perform: loadIfEditing)
        .onDisappear {
            if isEditing { persist() }
        }
        .onChange(of: scenePhase) { _, phase in
            if isEditing, phase != .active { persist() }
        }
        .onChange(of: snapshot) {
            // Save as you go, so nothing is lost even if the app is closed on this page.
            if isEditing { persist() }
        }
    }

    @ViewBuilder
    private var loggedOnlySections: some View {
            Section {
                HStack(spacing: 8) {
                    ForEach(DrinkRating.allCases) { option in
                        Button {
                            rating = rating == option ? nil : option
                        } label: {
                            Text(option.title)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .foregroundStyle(rating == option ? option.textColor : AppTheme.primaryText)
                                .background(
                                    rating == option ? option.color : AppTheme.photoPlaceholder,
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("Rating")
            } footer: {
                Text("Optional. Tap again to clear.")
            }

            Section {
                TextField("$16", text: $price)
                    .keyboardType(.numbersAndPunctuation)
                    .onSubmit { price = trimmedPrice ?? "" }
            } header: {
                Text("Price")
            } footer: {
                Text("Just a number means US dollars. Type another currency, like ¥88, to keep it.")
            }

            Section("When") {
                DatePicker("Date", selection: $date, in: ...Date.now.addingTimeInterval(24 * 60 * 60), displayedComponents: .date)
            }

            whereSection
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showingDeleteConfirm = true
            } label: {
                Text(isRecipe ? "Delete recipe" : "Delete drink")
                    .frame(maxWidth: .infinity)
            }
            // Attached here so the confirmation points at this button.
            .confirmationDialog(isRecipe ? "Delete this recipe?" : "Delete this drink?",
                                isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive, action: deleteDrink)
            } message: {
                Text(isRecipe ? "Drinks you logged from it are kept." : "This can't be undone.")
            }
        } footer: {
            Text("Changes are saved automatically.")
        }
    }

    private var markAsMadeSection: some View {
        Section {
            Button(action: markAsMade) {
                Label("Mark as Made", systemImage: "checkmark.circle")
                    .font(.headline)
            }
            ForEach(madeDrinks) { drink in
                Button {
                    drinkFilter.open(drink)
                } label: {
                    HStack {
                        Text(drink.createdAt.formatted(date: .abbreviated, time: .omitted))
                            .foregroundStyle(AppTheme.primaryText)
                        Spacer()
                        if let rating = drink.drinkRating {
                            RatingBadge(rating: rating)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(AppTheme.tertiaryText)
                    }
                }
            }
        } header: {
            Text(madeDrinks.isEmpty ? "Not made yet" : (madeDrinks.count == 1 ? "Made once" : "Made \(madeDrinks.count) times"))
        } footer: {
            Text("Mark as Made logs a copy in Drinks, dated today, to rate and photograph. The recipe stays here.")
        }
    }

    private var sourceSection: some View {
        Section {
            TextField("Paste a post link", text: $sourceURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if let link = trimmedSourceURL.flatMap(URL.init(string:)), link.scheme != nil {
                Link(destination: link) {
                    Label("Open original post", systemImage: "arrow.up.right.square")
                }
            }
        } header: {
            Text("Source")
        } footer: {
            Text("Instagram, Xiaohongshu or any link, to go back to the original video.")
        }
    }

    private var ingredientsSection: some View {
        Section {
            ForEach($ingredients) { $row in
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("Amount", text: $row.amount)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focus, equals: .amount(row.id))
                            .foregroundStyle(AppTheme.secondaryText)
                        if amountDisplay != .asWritten, IngredientAmount.canConvert(row.amount) {
                            Text("= \(IngredientAmount.display(row.amount, as: amountDisplay))")
                                .font(.caption)
                                .foregroundStyle(AppTheme.tertiaryText)
                        }
                    }
                    .frame(width: 76, alignment: .leading)
                    TextField("Ingredient", text: $row.text, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .focused($focus, equals: .name(row.id))
                    if ingredients.count > 1 {
                        Button(role: .destructive) {
                            ingredients.removeAll { $0.id == row.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Button {
                let row = IngredientRow()
                ingredients.append(row)
                focus = .amount(row.id)
            } label: {
                Label("Add ingredient", systemImage: "plus.circle")
            }
        } header: {
            HStack {
                Text("Ingredients")
                Spacer()
                if ingredients.contains(where: { IngredientAmount.canConvert($0.amount) }) {
                    // Shows each oz / ml / cl amount converted underneath; what you typed stays as is.
                    Menu {
                        Picker("Convert Amounts", selection: $amountDisplay) {
                            ForEach(AmountDisplay.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                    } label: {
                        Label(amountDisplay == .asWritten ? "Convert" : amountDisplay.title, systemImage: "arrow.left.arrow.right")
                            .font(.subheadline)
                    }
                }
            }
            .textCase(nil)
        } footer: {
            Text("Amount is optional, written any way you like. Type a comma after an ingredient to start the next one.")
        }
        .onChange(of: ingredients) {
            // Let the text field finish its edit before rows move under it.
            Task { @MainActor in splitAtCommas() }
        }
    }

    private var whereSection: some View {
        Section("Where") {
            Button {
                showingPlaceSearch = true
            } label: {
                HStack {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(AppTheme.accent)
                    if let placeName, !placeName.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(placeName)
                                .foregroundStyle(AppTheme.primaryText)
                            if let placeAddress, !placeAddress.isEmpty {
                                Text(placeAddress)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.secondaryText)
                            }
                        }
                    } else {
                        Text("Search or enter a place")
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(AppTheme.tertiaryText)
                }
            }
            .buttonStyle(.plain)

            if let placeName, !placeName.isEmpty {
                PlaceMapsMenu(placeName: placeName, placeAddress: placeAddress, latitude: latitude, longitude: longitude) {
                    Label("Open in Maps", systemImage: "map")
                        .foregroundStyle(AppTheme.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }

                Button("Clear place", role: .destructive) {
                    self.placeName = nil
                    placeAddress = nil
                    latitude = nil
                    longitude = nil
                }
            }
        }
    }

    private func unitButtons(for id: UUID) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(IngredientAmount.quickUnits, id: \.self) { unit in
                    Button(unit) {
                        setUnit(unit, for: id)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    /// "2" + oz → "2 oz", replacing a unit already there, then moves on to the ingredient name.
    private func setUnit(_ unit: String, for id: UUID) {
        guard let index = ingredients.firstIndex(where: { $0.id == id }) else { return }
        let number = ingredients[index].amount
            .replacingOccurrences(of: #"\s*[A-Za-z][A-Za-z ]*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        ingredients[index].amount = number.isEmpty ? unit : "\(number) \(unit)"
        focus = .name(id)
    }

    private var title: String {
        switch mode {
        case .add: return "New drink"
        case .addRecipe: return "New recipe"
        case .edit(let cocktail): return cocktail.isRecipeEntry ? "Recipe" : "Drink"
        }
    }

    /// "lime, salt" typed or pasted into one row becomes two rows; a trailing comma
    /// opens an empty row and moves the cursor there.
    private func splitAtCommas() {
        let commas: Set<Character> = [",", "，", "、"]
        guard let index = ingredients.firstIndex(where: { $0.text.contains(where: commas.contains) }) else { return }

        let pieces = ingredients[index].text
            .split(omittingEmptySubsequences: false, whereSeparator: commas.contains)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let kept = pieces.enumerated()
            .filter { !$0.element.isEmpty || $0.offset == pieces.count - 1 }
            .map(\.element)

        // The first piece keeps the row (and its cursor); the rest become new rows.
        var rows = kept.map { IngredientRow(text: $0) }
        rows[0].id = ingredients[index].id
        rows[0].amount = ingredients[index].amount
        ingredients.replaceSubrange(index...index, with: rows)
        if let last = rows.last {
            // A new row starts at its amount, the way recipes are written ("2 oz Gin").
            focus = rows.count > 1 && last.text.isEmpty ? .amount(last.id) : .name(last.id)
        }
    }

    private func applyScan(_ result: MenuRecognitionResult) {
        name = result.cleanedName
        ingredients = IngredientRow.rows(result.cleanedIngredients.map { IngredientLine(name: $0, amount: "") })
        if !result.cleanedPrice.isEmpty {
            price = Cocktail.normalizedPrice(result.cleanedPrice) ?? ""
        }
        // The menu photo is added after any photos already there, so a drink photo stays the cover.
        if let scanned = result.photoData, !photos.contains(scanned) {
            photos.append(scanned)
        }
    }

    /// Once only: coming back from the photo viewer or menu scan must not undo edits.
    private func loadIfEditing() {
        guard !hasLoaded, case .edit(let cocktail) = mode else { return }
        hasLoaded = true
        name = cocktail.name
        ingredients = IngredientRow.rows(cocktail.ingredientLines)
        rating = cocktail.drinkRating
        photos = cocktail.photos
        placeName = cocktail.placeName
        placeAddress = cocktail.placeAddress
        latitude = cocktail.latitude
        longitude = cocktail.longitude
        price = cocktail.trimmedPrice ?? ""
        date = cocktail.createdAt
        sourceURL = cocktail.sourceURL ?? ""
        notes = cocktail.notes ?? ""
        original = snapshot
    }

    /// Puts every field back as it was when the page opened; saving as you go then
    /// writes that back to the drink.
    private func undoChanges() {
        guard let original else { return }
        name = original.name
        ingredients = original.ingredients
        photos = original.photos
        placeName = original.placeName
        placeAddress = original.placeAddress
        latitude = original.latitude
        longitude = original.longitude
        price = original.price
        date = original.date
        rating = original.rating
        sourceURL = original.sourceURL
        notes = original.notes
        persist()
    }

    /// Everything on the page, to notice any edit.
    private var snapshot: EditorSnapshot {
        EditorSnapshot(
            name: name, ingredients: ingredients, photos: photos,
            placeName: placeName, placeAddress: placeAddress, latitude: latitude, longitude: longitude,
            price: price, date: date, rating: rating, sourceURL: sourceURL, notes: notes
        )
    }

    private var trimmedNotes: String? {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var trimmedPrice: String? {
        Cocktail.normalizedPrice(price)
    }

    private var ingredientFields: (names: [String], amounts: [String]?) {
        let lines = ingredients
            .map {
                IngredientLine(
                    name: $0.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    amount: $0.amount.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            .filter { !$0.name.isEmpty }
        let amounts = lines.contains { !$0.amount.isEmpty } ? lines.map(\.amount) : nil
        return (lines.map(\.name), amounts)
    }

    private func save() {
        guard canSave else {
            showingValidationAlert = true
            return
        }
        let fields = ingredientFields
        modelContext.insert(Cocktail(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            ingredients: fields.names,
            photoData: photos.first,
            morePhotoData: photos.count > 1 ? Array(photos.dropFirst()) : nil,
            placeName: placeName,
            placeAddress: placeAddress,
            latitude: latitude,
            longitude: longitude,
            price: trimmedPrice,
            ingredientAmounts: fields.amounts,
            rating: isRecipe ? nil : rating,
            createdAt: isRecipe ? .now : date,
            isRecipe: isRecipe,
            sourceURL: isRecipe ? trimmedSourceURL : nil,
            notes: trimmedNotes
        ))
        try? modelContext.save()
        dismiss()
    }

    /// Writes the page back to the logged drink. Skipped if everything was cleared,
    /// so the drink keeps what it had rather than becoming empty.
    private func persist() {
        guard case .edit(let cocktail) = mode, hasLoaded, !isDeleted, canSave else { return }
        let fields = ingredientFields
        cocktail.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        cocktail.ingredients = fields.names
        cocktail.ingredientAmounts = fields.amounts
        cocktail.drinkRating = rating
        cocktail.photos = photos
        cocktail.placeName = placeName
        cocktail.placeAddress = placeAddress
        cocktail.latitude = latitude
        cocktail.longitude = longitude
        cocktail.price = trimmedPrice
        cocktail.notes = trimmedNotes
        if cocktail.isRecipeEntry {
            cocktail.sourceURL = trimmedSourceURL
        } else {
            cocktail.createdAt = date
        }
        // Write now; SwiftData's own autosave can be too late if the app is closed right after.
        try? modelContext.save()
    }

    /// Logs a copy of this recipe as a drink made today and opens it in Drinks.
    private func markAsMade() {
        guard case .edit(let recipe) = mode else { return }
        persist()
        let fields = ingredientFields
        let drink = Cocktail(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            ingredients: fields.names,
            ingredientAmounts: fields.amounts,
            createdAt: .now,
            recipeID: recipe.id
        )
        modelContext.insert(drink)
        try? modelContext.save()
        drinkFilter.open(drink)
    }

    private func deleteDrink() {
        guard case .edit(let cocktail) = mode else { return }
        isDeleted = true
        modelContext.delete(cocktail)
        try? modelContext.save()
        dismiss()
    }
}

/// One editable ingredient line, with a stable id so rows can be inserted while typing.
private struct IngredientRow: Identifiable, Equatable {
    var id = UUID()
    var text = ""
    var amount = ""

    static func rows(_ lines: [IngredientLine]) -> [IngredientRow] {
        lines.isEmpty ? [IngredientRow()] : lines.map { IngredientRow(text: $0.name, amount: $0.amount) }
    }
}

private struct EditorSnapshot: Equatable {
    var name: String
    var ingredients: [IngredientRow]
    var photos: [Data]
    var placeName: String?
    var placeAddress: String?
    var latitude: Double?
    var longitude: Double?
    var price: String
    var date: Date
    var rating: DrinkRating?
    var sourceURL: String
    var notes: String
}

private enum IngredientField: Hashable {
    case amount(UUID)
    case name(UUID)
}
