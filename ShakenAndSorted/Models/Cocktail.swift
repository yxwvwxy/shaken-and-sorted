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

    var displayTitle: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let first = ingredients.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return first
        }
        return "Untitled"
    }

    var ingredientSummary: String {
        let cleaned = ingredients
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return "" }
        if cleaned.count <= 3 {
            return cleaned.joined(separator: " · ")
        }
        return cleaned.prefix(3).joined(separator: " · ") + "…"
    }

    var hasPlace: Bool {
        !(placeName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    static func canSave(name: String, ingredients: [String]) -> Bool {
        let hasName = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasIngredient = ingredients.contains {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return hasName || hasIngredient
    }
}
