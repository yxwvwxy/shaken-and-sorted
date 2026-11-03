import Foundation
import SwiftData

/// What an ingredient does in the drink. Spirits are split by kind.
enum IngredientCategory: String, CaseIterable, Identifiable {
    case whiskey
    case gin
    case vodka
    case rum
    case agave
    case brandy
    case otherSpirits
    case liqueurs
    case aperitifs
    case bitters
    case citrus
    case sweeteners
    case juicesAndFresh
    case mixers
    case texture
    case garnishes
    case uncategorized

    var id: String { rawValue }

    var title: String {
        switch self {
        case .whiskey: return "Whiskey"
        case .gin: return "Gin"
        case .vodka: return "Vodka"
        case .rum: return "Rum"
        case .agave: return "Tequila & Mezcal"
        case .brandy: return "Brandy"
        case .otherSpirits: return "Other Spirits"
        case .liqueurs: return "Liqueurs"
        case .aperitifs: return "Vermouth & Aperitifs"
        case .bitters: return "Bitters"
        case .citrus: return "Citrus & Acids"
        case .sweeteners: return "Sweeteners & Syrups"
        case .juicesAndFresh: return "Juices & Fresh"
        case .mixers: return "Mixers & Bubbles"
        case .texture: return "Dairy & Texture"
        case .garnishes: return "Garnishes"
        case .uncategorized: return "Uncategorized"
        }
    }

    /// Best guess from the words in the name. Checked in order, so "Orange Bitters" is
    /// bitters, "Brown Butter-Washed Rye" is whiskey and "Lime Juice" is citrus.
    static func guess(for name: String) -> IngredientCategory {
        let text = IngredientKey.normalized(name)
        for (category, pattern) in rules where text.range(of: pattern, options: .regularExpression) != nil {
            return category
        }
        return .uncategorized
    }

    private static let rules: [(IngredientCategory, String)] = [
        (.garnishes, ["peel", "twist", "zest", "wheel", "wedge", "garnish", "rim", "maraschino cherry", "cocktail cherry", "luxardo cherry", "olive"]),
        (.bitters, ["bitters", "angostura", "peychaud's", "peychauds"]),
        (.liqueurs, ["liqueur", "chartreuse", "cointreau", "triple sec", "curaçao", "curacao", "grand marnier", "maraschino",
                     "heering", "amaretto", "kahlua", "kahlúa", "falernum", "st-germain", "st germain", "crème de", "creme de",
                     "cassis", "frangelico", "drambuie", "galliano", "bénédictine", "benedictine", "midori", "limoncello",
                     "allspice dram", "pimento dram", "sloe gin"]),
        (.aperitifs, ["vermouth", "antica", "carpano", "dolin", "cocchi", "lillet", "sherry", "fino", "amontillado",
                      "oloroso", "port", "madeira", "campari", "aperol", "amaro", "amari", "cynar", "fernet", "montenegro",
                      "averna", "nonino", "suze", "punt e mes", "bonal", "quinquina", "aperitivo"]),
        (.whiskey, ["whiskey", "whisky", "bourbon", "rye", "scotch", "jack daniel's", "jack daniels", "knob creek",
                    "bulleit", "rittenhouse", "wild turkey", "maker's mark", "laphroaig", "islay"]),
        (.gin, ["gin", "genever", "old tom"]),
        (.vodka, ["vodka"]),
        (.rum, ["rum", "rhum", "cachaça", "cachaca", "agricole"]),
        (.agave, ["tequila", "mezcal", "reposado", "añejo", "anejo", "raicilla", "sotol"]),
        (.brandy, ["brandy", "cognac", "armagnac", "calvados", "pisco", "applejack", "grappa", "eau de vie"]),
        (.otherSpirits, ["absinthe", "baijiu", "shochu", "soju", "aquavit", "akvavit", "arrack", "sake"]),
        (.mixers, ["soda", "tonic", "ginger beer", "ginger ale", "cola", "champagne", "prosecco", "cava", "sparkling",
                   "seltzer", "lemonade"]),
        (.texture, ["egg", "egg white", "cream", "milk", "butter", "coconut cream", "coconut milk", "aquafaba", "yogurt"]),
        (.sweeteners, ["syrup", "sugar", "demerara", "demarara", "honey", "agave nectar", "grenadine", "orgeat", "maple",
                       "gomme", "cordial"]),
        (.citrus, ["lemon", "lime", "grapefruit", "yuzu", "citric", "verjus", "vinegar", "shrub", "acid", "calamansi"]),
        (.juicesAndFresh, ["juice", "pineapple", "cranberry", "tomato", "cucumber", "mint", "basil", "watermelon",
                           "strawberry", "apple", "passion fruit", "mango", "ginger", "chili", "pepper", "celery", "peach",
                           "raspberry", "blackberry", "orange", "coconut water", "tea", "coffee", "espresso"]),
        (.garnishes, ["nutmeg", "cinnamon", "salt", "cherry"]),
    ].map { category, words in
        // Whole words only ("gin" is not in "ginger"), plural allowed ("bourbons").
        let alternatives = words.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        return (category, "(?<![a-z])(?:\(alternatives))s?(?![a-z])")
    }
}

/// One spelling for the same ingredient across drinks: "Antica Vermouth", "antica  vermouth".
enum IngredientKey {
    static func normalized(_ name: String) -> String {
        name
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

/// A category picked by hand for an ingredient, replacing the guess.
@Model
final class IngredientCategoryChoice {
    @Attribute(.unique) var key: String
    var categoryRaw: String

    init(key: String, category: IngredientCategory) {
        self.key = key
        self.categoryRaw = category.rawValue
    }

    var category: IngredientCategory {
        get { IngredientCategory(rawValue: categoryRaw) ?? .uncategorized }
        set { categoryRaw = newValue.rawValue }
    }
}
