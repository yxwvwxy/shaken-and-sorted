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
    @State private var ingredients: [String] = [""]
    @State private var photoData: Data?
    @State private var placeName: String?
    @State private var placeAddress: String?
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var showingPlaceSearch = false
    @State private var showingMenuScan = false
    @State private var showingValidationAlert = false

    private var canSave: Bool {
        Cocktail.canSave(name: name, ingredients: ingredients, photoData: photoData)
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
                    Text("Photo a menu, circle one drink, then edit the name and ingredients before saving.")
                }

                Section("Name") {
                    TextField("Cocktail name", text: $name)
                        .textInputAutocapitalization(.words)
                }

                Section("Ingredients") {
                    ForEach(ingredients.indices, id: \.self) { index in
                        HStack {
                            TextField("Ingredient", text: $ingredients[index])
                                .textInputAutocapitalization(.never)
                            if ingredients.count > 1 {
                                Button(role: .destructive) {
                                    ingredients.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Button {
                        ingredients.append("")
                    } label: {
                        Label("Add ingredient", systemImage: "plus.circle")
                    }
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
            .alert("Add a name, an ingredient, or a photo", isPresented: $showingValidationAlert) {
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

    private func applyScan(_ result: MenuRecognitionResult) {
        name = result.cleanedName
        ingredients = result.cleanedIngredients.isEmpty ? [""] : result.cleanedIngredients
    }

    private func loadIfEditing() {
        guard case .edit(let cocktail) = mode else { return }
        name = cocktail.name
        ingredients = cocktail.ingredients.isEmpty ? [""] : cocktail.ingredients
        photoData = cocktail.photoData
        placeName = cocktail.placeName
        placeAddress = cocktail.placeAddress
        latitude = cocktail.latitude
        longitude = cocktail.longitude
    }

    private func save() {
        guard canSave else {
            showingValidationAlert = true
            return
        }

        let cleanedIngredients = ingredients
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
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
                longitude: longitude
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
        }

        dismiss()
    }
}
