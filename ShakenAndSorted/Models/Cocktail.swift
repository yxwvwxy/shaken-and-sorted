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
    /// True for a saved recipe you want to make; nil or false for a drink you logged.
    var isRecipe: Bool?
    /// Where a recipe came from, such as an Instagram or Xiaohongshu post.
    var sourceURL: String?
    /// Anything else worth remembering: how it tasted, the method, who made it.
    var notes: String?
    /// Left by older versions, which logged a separate copy for each recipe made;
    /// those copies are folded back into their recipe at launch.
    var recipeID: UUID?
    /// A recipe you've made: it then shows in Drinks too, as the same entry.
    var isMade: Bool?

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
        createdAt: Date = .now,
        isRecipe: Bool = false,
        sourceURL: String? = nil,
        recipeID: UUID? = nil,
        notes: String? = nil
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
        self.isRecipe = isRecipe ? true : nil
        self.sourceURL = sourceURL
        self.recipeID = recipeID
        self.notes = notes
    }

    var isRecipeEntry: Bool { isRecipe == true }
    var isMadeRecipe: Bool { isRecipe == true && isMade == true }

    /// What Drinks shows: drinks you logged, and recipes you've made. Drinks from before
    /// recipes existed have no flag at all, and the store treats "no value != true" as
    /// false, so nil is checked too.
    static let loggedDrinks = #Predicate<Cocktail> { cocktail in
        !(cocktail.isRecipe ?? false) || (cocktail.isMade ?? false)
    }
    static let recipes = #Predicate<Cocktail> { $0.isRecipe == true }

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
        Self.normalizedPrice(price ?? "")
    }

    /// A bare number is taken as US dollars ("19" → "$19", "12.50" → "$12.50");
    /// anything with its own currency ("¥88", "€12", "15 CAD") is kept as written.
    static func normalizedPrice(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.range(of: #"^\d+([.,]\d{1,2})?$"#, options: .regularExpression) != nil {
            return "$" + trimmed
        }
        return trimmed
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
