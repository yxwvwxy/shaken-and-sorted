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
    @Query private var translations: [IngredientTranslation]
    @State private var editingChinese: ChineseEdit?
    @State private var chineseDraft = ""
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
        Cocktail.canSave(name: name, ingredients: ingredients.map(\.text), photoData: photos.first, placeName: placeName)
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

    private var isMade: Bool {
        if case .edit(let cocktail) = mode { return cocktail.isMadeRecipe }
        return false
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
                    Label("Scan a menu or recipe", systemImage: "menucard")
                }
            } footer: {
                Text("Photo a menu, recipe card or screenshot, highlight one drink, then edit anything before saving.")
            }

            Section("Name") {
                TextField("Cocktail name", text: $name, axis: .vertical)
                    .textInputAutocapitalization(.words)
            }

            // Drinks and recipes share every section, in the same order.
            ingredientsSection

            ratingSection

            Section("Notes") {
                TextField("How it tasted, the method, anything to remember", text: $notes, axis: .vertical)
                    .lineLimit(3...)
            }

            Section("Photo") {
                PhotoPickerField(photos: $photos)
            }

            whenSection

            whereSection

            // A bought drink has a price; a recipe (made or not) has the post it came from.
            if isRecipe {
                sourceSection
            } else {
                priceSection
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
            Text("Add at least one of these: a name, an ingredient, a place, or a photo.")
        }
        .alert(
            editingChinese.map { "Chinese Name · \($0.name)" } ?? "Chinese Name",
            isPresented: Binding(get: { editingChinese != nil }, set: { if !$0 { editingChinese = nil } })
        ) {
            TextField("Chinese name", text: $chineseDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save") { saveChinese() }
        } message: {
            Text("Changes this ingredient in every drink. Leave it empty to translate again.")
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

    private var ratingSection: some View {
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
    }

    private var priceSection: some View {
            Section {
                TextField("$16", text: $price)
                    .keyboardType(.numbersAndPunctuation)
                    .onSubmit { price = trimmedPrice ?? "" }
            } header: {
                Text("Price")
            } footer: {
                Text("Just a number means US dollars. Type another currency, like ¥88, to keep it.")
            }
    }

    private var whenSection: some View {
            Section("When") {
                DatePicker("Date", selection: $date, in: ...Date.now.addingTimeInterval(24 * 60 * 60), displayedComponents: .date)
            }
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

    /// A recipe is either to make or made. Made puts this same entry in Drinks too,
    /// dated the day you made it; To Make takes it out of Drinks again.
    private var markAsMadeSection: some View {
        Section {
            if isMade {
                Label("Made · \(date.formatted(date: .abbreviated, time: .omitted))", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.primaryText)
                Button(action: markAsToMake) {
                    Label("Mark as To Make", systemImage: "arrow.uturn.backward.circle")
                }
            } else {
                Button(action: markAsMade) {
                    Label("Mark as Made", systemImage: "circle")
                        .font(.headline)
                }
            }
        } header: {
            Text(isMade ? "Made" : "To make")
        } footer: {
            Text(isMade ? "Also in Drinks. Rate it below." : "Shows it in Drinks too, dated today.")
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
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("Ingredient", text: $row.text, axis: .vertical)
                            .textInputAutocapitalization(.never)
                            .focused($focus, equals: .name(row.id))
                        let key = IngredientKey.normalized(row.text)
                        if !key.isEmpty {
                            // Tap to fix the Chinese name; it changes for every drink with this ingredient.
                            Button {
                                editingChinese = ChineseEdit(key: key, name: row.text.trimmingCharacters(in: .whitespaces))
                                chineseDraft = chineseName(for: row.text) ?? ""
                            } label: {
                                let chinese = chineseName(for: row.text)
                                Text(chinese ?? "+ Chinese name")
                                    .font(.caption)
                                    .foregroundStyle(chinese == nil ? AppTheme.tertiaryText : AppTheme.secondaryText)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
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

    /// Keeps a hand-typed Chinese name; an empty one lets the phone translate again.
    private func saveChinese() {
        guard let edit = editingChinese else { return }
        let typed = chineseDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = translations.first { $0.key == edit.key }
        if typed.isEmpty {
            if let existing { modelContext.delete(existing) }
        } else if let existing {
            existing.chinese = typed
            existing.isManual = true
        } else {
            modelContext.insert(IngredientTranslation(key: edit.key, chinese: typed, isManual: true))
        }
        try? modelContext.save()
        editingChinese = nil
    }

    /// The saved Chinese name, or the glossary's for an ingredient not saved yet.
    private func chineseName(for ingredient: String) -> String? {
        chineseNames[IngredientKey.normalized(ingredient)] ?? CocktailGlossary.chinese(for: ingredient)
    }

    private var chineseNames: [String: String] {
        Dictionary(translations.map { ($0.key, $0.chinese) }, uniquingKeysWith: { first, _ in first })
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
            rating: rating,
            createdAt: date,
            isRecipe: isRecipe,
            sourceURL: trimmedSourceURL,
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
        cocktail.sourceURL = trimmedSourceURL
        cocktail.createdAt = date
        // Write now; SwiftData's own autosave can be too late if the app is closed right after.
        try? modelContext.save()
    }

    private func markAsMade() {
        guard case .edit(let recipe) = mode else { return }
        date = .now
        persist()
        recipe.isMade = true
        try? modelContext.save()
    }

    private func markAsToMake() {
        guard case .edit(let recipe) = mode else { return }
        recipe.isMade = nil
        try? modelContext.save()
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

private struct ChineseEdit {
    let key: String
    let name: String
}

private enum IngredientField: Hashable {
    case amount(UUID)
    case name(UUID)
}
