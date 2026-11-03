import SwiftUI
import SwiftData

enum CocktailEditorMode {
    case add
    case edit(Cocktail)
}

/// Adding a drink (a sheet with Cancel / Save) or a logged drink's own page, which is
/// editable right away and saves changes when you leave it.
struct CocktailEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

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
    @State private var amountDisplay: AmountDisplay = .asWritten
    @State private var showingPlaceSearch = false
    @State private var showingMenuScan = false
    @State private var showingValidationAlert = false
    @State private var showingDeleteConfirm = false
    @State private var hasLoaded = false
    @State private var isDeleted = false
    @FocusState private var focus: IngredientField?

    private var canSave: Bool {
        Cocktail.canSave(name: name, ingredients: ingredients.map(\.text), photoData: photos.first, placeName: placeName)
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var body: some View {
        switch mode {
        case .add:
            NavigationStack { form }
                .tint(AppTheme.accent)
        case .edit:
            // Pushed onto the list's navigation stack, so no stack of its own.
            form
        }
    }

    private var form: some View {
        Form {
            Section {
                Button {
                    showingMenuScan = true
                } label: {
                    Label("Scan from menu", systemImage: "menucard")
                }
            } footer: {
                Text("Photo a menu, highlight one drink, then edit anything before saving.")
            }

            Section("Name") {
                TextField("Cocktail name", text: $name, axis: .vertical)
                    .textInputAutocapitalization(.words)
            }

            ingredientsSection

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

            Section("Price") {
                TextField("$16", text: $price)
            }

            Section("When") {
                DatePicker("Date", selection: $date, in: ...Date.now.addingTimeInterval(24 * 60 * 60), displayedComponents: .date)
            }

            whereSection

            Section("Photo") {
                PhotoPickerField(photos: $photos)
            }

            if isEditing {
                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Text("Delete drink")
                            .frame(maxWidth: .infinity)
                    }
                    // Attached here so the confirmation points at this button.
                    .confirmationDialog("Delete this drink?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
                        Button("Delete", role: .destructive, action: deleteDrink)
                    } message: {
                        Text("This can't be undone.")
                    }
                } footer: {
                    Text("Changes are saved automatically.")
                }
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
        case .edit: return "Drink"
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
            price = result.cleanedPrice
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
        price = cocktail.price ?? ""
        date = cocktail.createdAt
    }

    /// Everything on the page, to notice any edit.
    private var snapshot: EditorSnapshot {
        EditorSnapshot(
            name: name, ingredients: ingredients, photos: photos,
            placeName: placeName, placeAddress: placeAddress, latitude: latitude, longitude: longitude,
            price: price, date: date, rating: rating
        )
    }

    private var trimmedPrice: String? {
        let trimmed = price.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
            createdAt: date
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
        cocktail.createdAt = date
        // Write now; SwiftData's own autosave can be too late if the app is closed right after.
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
}

private enum IngredientField: Hashable {
    case amount(UUID)
    case name(UUID)
}
