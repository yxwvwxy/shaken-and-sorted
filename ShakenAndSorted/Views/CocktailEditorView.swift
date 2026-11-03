import SwiftUI
import SwiftData

enum CocktailEditorMode {
    case add
    case edit(Cocktail)
}

struct CocktailEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let mode: CocktailEditorMode

    @State private var name: String = ""
    @State private var ingredients: [IngredientRow] = [IngredientRow()]
    @State private var photoData: Data?
    @State private var placeName: String?
    @State private var placeAddress: String?
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var price = ""
    @State private var date = Date.now
    @State private var showingPlaceSearch = false
    @State private var showingMenuScan = false
    @State private var showingValidationAlert = false
    @FocusState private var focusedIngredient: IngredientRow.ID?

    private var canSave: Bool {
        Cocktail.canSave(name: name, ingredients: ingredients.map(\.text), photoData: photoData, placeName: placeName)
    }

    var body: some View {
        NavigationStack {
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

                Section {
                    ForEach($ingredients) { $row in
                        HStack {
                            TextField("Ingredient", text: $row.text, axis: .vertical)
                                .textInputAutocapitalization(.never)
                                .focused($focusedIngredient, equals: row.id)
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
                        focusedIngredient = row.id
                    } label: {
                        Label("Add ingredient", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Ingredients")
                } footer: {
                    Text("Type a comma to start the next ingredient.")
                }
                .onChange(of: ingredients) {
                    // Let the text field finish its edit before rows move under it.
                    Task { @MainActor in splitAtCommas() }
                }

                Section("Price") {
                    TextField("$16", text: $price)
                }

                Section("When") {
                    DatePicker("Date", selection: $date, in: ...Date.now.addingTimeInterval(24 * 60 * 60), displayedComponents: .date)
                }

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

                    if placeName != nil {
                        Button("Clear place", role: .destructive) {
                            placeName = nil
                            placeAddress = nil
                            latitude = nil
                            longitude = nil
                        }
                    }
                }

                Section("Photo") {
                    PhotoPickerField(photoData: $photoData)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .alert("Add a name, an ingredient, a photo, or a place", isPresented: $showingValidationAlert) {
                Button("OK", role: .cancel) {}
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
        }
        .tint(AppTheme.accent)
    }

    private var title: String {
        switch mode {
        case .add: return "New drink"
        case .edit: return "Edit drink"
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
        ingredients.replaceSubrange(index...index, with: rows)
        focusedIngredient = rows.last?.id
    }

    private func applyScan(_ result: MenuRecognitionResult) {
        name = result.cleanedName
        ingredients = IngredientRow.rows(result.cleanedIngredients)
        if !result.cleanedPrice.isEmpty {
            price = result.cleanedPrice
        }
        // Keep a drink photo already picked; otherwise the menu photo becomes the record's photo.
        if photoData == nil, let scanned = result.photoData {
            photoData = scanned
        }
    }

    private func loadIfEditing() {
        guard case .edit(let cocktail) = mode else { return }
        name = cocktail.name
        ingredients = IngredientRow.rows(cocktail.ingredients)
        photoData = cocktail.photoData
        placeName = cocktail.placeName
        placeAddress = cocktail.placeAddress
        latitude = cocktail.latitude
        longitude = cocktail.longitude
        price = cocktail.price ?? ""
        date = cocktail.createdAt
    }

    private var trimmedPrice: String? {
        let trimmed = price.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func save() {
        guard canSave else {
            showingValidationAlert = true
            return
        }

        let cleanedIngredients = ingredients
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        switch mode {
        case .add:
            let cocktail = Cocktail(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                ingredients: cleanedIngredients,
                photoData: photoData,
                placeName: placeName,
                placeAddress: placeAddress,
                latitude: latitude,
                longitude: longitude,
                price: trimmedPrice,
                createdAt: date
            )
            modelContext.insert(cocktail)
        case .edit(let cocktail):
            cocktail.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            cocktail.ingredients = cleanedIngredients
            cocktail.photoData = photoData
            cocktail.placeName = placeName
            cocktail.placeAddress = placeAddress
            cocktail.latitude = latitude
            cocktail.longitude = longitude
            cocktail.price = trimmedPrice
            cocktail.createdAt = date
        }

        dismiss()
    }
}

/// One editable ingredient line, with a stable id so rows can be inserted while typing.
private struct IngredientRow: Identifiable, Equatable {
    var id = UUID()
    var text = ""

    static func rows(_ texts: [String]) -> [IngredientRow] {
        texts.isEmpty ? [IngredientRow()] : texts.map { IngredientRow(text: $0) }
    }
}
