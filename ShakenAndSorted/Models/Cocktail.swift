import Foundation
import SwiftData

@Model
final class Cocktail {
    var id: UUID
    var name: String
    var ingredients: [String]
    var photoData: Data?
    var placeName: String?
    var placeAddress: String?
    var latitude: Double?
    var longitude: Double?
    var createdAt: Date

    init(
        name: String = "",
        ingredients: [String] = [],
        photoData: Data? = nil,
        placeName: String? = nil,
        placeAddress: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        createdAt: Date = .now
    ) {
        self.id = UUID()
        self.name = name
        self.ingredients = ingredients
        self.photoData = photoData
        self.placeName = placeName
        self.placeAddress = placeAddress
        self.latitude = latitude
        self.longitude = longitude
        self.createdAt = createdAt
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasName: Bool {
        !trimmedName.isEmpty
    }

    var displayTitle: String {
        if hasName { return trimmedName }
        if let first = cleanedIngredients.first {
            return first
        }
        return "Untitled"
    }

    var cleanedIngredients: [String] {
        ingredients
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var ingredientSummary: String {
        cleanedIngredients.joined(separator: " · ")
    }

    var hasPlace: Bool {
        !(placeName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var hasPhoto: Bool {
        !(photoData?.isEmpty ?? true)
    }

    static func canSave(name: String, ingredients: [String], photoData: Data? = nil) -> Bool {
        let hasName = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasIngredient = ingredients.contains {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let hasPhoto = photoData.map { !$0.isEmpty } ?? false
        return hasName || hasIngredient || hasPhoto
    }
}
