import Foundation
import SwiftData

@Model
final class Cocktail {
    var id: UUID
    var name: String
    var ingredients: [String]
    /// The cover photo, shown in the list.
    var photoData: Data?
    /// Photos after the cover, in order.
    var morePhotoData: [Data]?
    var placeName: String?
    var placeAddress: String?
    var latitude: Double?
    var longitude: Double?
    /// As printed on the menu, currency included ("$19", "¥88").
    var price: String?
    /// Amount for each ingredient, same order as `ingredients` ("2 oz", "2 dashes", "" when not noted).
    var ingredientAmounts: [String]?
    /// `DrinkRating` raw value; nil until rated.
    var rating: Int?
    var createdAt: Date

    init(
        name: String = "",
        ingredients: [String] = [],
        photoData: Data? = nil,
        morePhotoData: [Data]? = nil,
        placeName: String? = nil,
        placeAddress: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        price: String? = nil,
        ingredientAmounts: [String]? = nil,
        rating: DrinkRating? = nil,
        createdAt: Date = .now
    ) {
        self.id = UUID()
        self.name = name
        self.ingredients = ingredients
        self.photoData = photoData
        self.morePhotoData = morePhotoData
        self.placeName = placeName
        self.placeAddress = placeAddress
        self.latitude = latitude
        self.longitude = longitude
        self.price = price
        self.ingredientAmounts = ingredientAmounts
        self.rating = rating?.rawValue
        self.createdAt = createdAt
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasName: Bool {
        !trimmedName.isEmpty
    }

    /// The name, or "Unnamed" for a drink logged without one.
    var displayTitle: String {
        hasName ? trimmedName : "Unnamed"
    }

    var cleanedIngredients: [String] {
        ingredients
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Ingredients with their amounts, skipping empty names.
    var ingredientLines: [IngredientLine] {
        let amounts = ingredientAmounts ?? []
        return ingredients.enumerated().compactMap { index, name in
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let amount = index < amounts.count ? amounts[index].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            return IngredientLine(name: name, amount: amount)
        }
    }

    var drinkRating: DrinkRating? {
        get { rating.flatMap(DrinkRating.init(rawValue:)) }
        set { rating = newValue?.rawValue }
    }

    var ingredientSummary: String {
        cleanedIngredients.joined(separator: " · ")
    }

    var trimmedPrice: String? {
        let trimmed = price?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    var hasPlace: Bool {
        !(placeName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    /// All photos, cover first.
    var photos: [Data] {
        get { [photoData].compactMap { $0 } + (morePhotoData ?? []) }
        set {
            photoData = newValue.first
            let rest = Array(newValue.dropFirst())
            morePhotoData = rest.isEmpty ? nil : rest
        }
    }

    var hasPhoto: Bool {
        !(photoData?.isEmpty ?? true)
    }

    static func canSave(
        name: String,
        ingredients: [String],
        photoData: Data? = nil,
        placeName: String? = nil
    ) -> Bool {
        let hasName = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasIngredient = ingredients.contains {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let hasPhoto = photoData.map { !$0.isEmpty } ?? false
        let hasPlace = !(placeName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        return hasName || hasIngredient || hasPhoto || hasPlace
    }
}

struct IngredientLine: Hashable {
    var name: String
    var amount: String
}

enum DrinkRating: Int, CaseIterable, Identifiable {
    case notForMe = 1
    case meh
    case notBad
    case loveIt

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .notForMe: return "Nuh uh"
        case .meh: return "Meh"
        case .notBad: return "Not bad"
        case .loveIt: return "Love it"
        }
    }
}
