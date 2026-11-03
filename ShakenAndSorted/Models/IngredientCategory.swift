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
        (.whiskey, ["whiskey", "whisky", "bourbon", "rye", "scotch", "single malt", "jack daniel's", "jack daniels",
                    "knob creek", "bulleit", "rittenhouse", "wild turkey", "maker's mark", "makers mark", "buffalo trace",
                    "woodford", "four roses", "elijah craig", "old forester", "evan williams", "eagle rare", "basil hayden",
                    "pikesville", "islay", "speyside", "laphroaig", "lagavulin", "ardbeg", "talisker", "glenlivet",
                    "glenfiddich", "macallan", "monkey shoulder", "johnnie walker", "dewar's", "famous grouse",
                    "highland park", "jameson", "redbreast", "bushmills", "teeling", "tullamore", "suntory", "nikka",
                    "hibiki", "yamazaki", "hakushu"]),
        (.gin, ["gin", "genever", "old tom"]),
        (.vodka, ["vodka"]),
        (.rum, ["rum", "rhum", "cachaça", "cachaca", "agricole"]),
        (.agave, ["tequila", "mezcal", "reposado", "añejo", "anejo", "raicilla", "sotol"]),
        (.brandy, ["brandy", "cognac", "armagnac", "calvados", "pisco", "applejack", "grappa", "eau de vie",
                   "hennessy", "rémy martin", "remy martin", "pierre ferrand", "courvoisier"]),
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
    ].map { category, words in (category, wordPattern(words)) }

    /// Whole words only ("gin" is not in "ginger"), plural allowed ("bourbons").
    static func wordPattern(_ words: [String]) -> String {
        let alternatives = words.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        return "(?<![a-z])(?:\(alternatives))s?(?![a-z])"
    }

    var subcategories: [IngredientSubcategory] {
        IngredientSubcategory.allCases.filter { $0.category == self }
    }
}

/// Finer kinds for the main spirits. Each category that has them always gets one,
/// falling back to "Other …" when the name doesn't say.
enum IngredientSubcategory: String, CaseIterable, Identifiable {
    case bourbon, rye, scotch, irish, japanese, otherWhiskey
    case whiteRum, agedRum, darkRum, agricole, otherRum
    case tequila, mezcal, otherAgave
    case cognac, armagnac, pisco, calvados, otherBrandy

    var id: String { rawValue }

    var category: IngredientCategory {
        switch self {
        case .bourbon, .rye, .scotch, .irish, .japanese, .otherWhiskey: return .whiskey
        case .whiteRum, .agedRum, .darkRum, .agricole, .otherRum: return .rum
        case .tequila, .mezcal, .otherAgave: return .agave
        case .cognac, .armagnac, .pisco, .calvados, .otherBrandy: return .brandy
        }
    }

    var title: String {
        switch self {
        case .bourbon: return "Bourbon"
        case .rye: return "Rye"
        case .scotch: return "Scotch"
        case .irish: return "Irish"
        case .japanese: return "Japanese"
        case .otherWhiskey: return "Other Whiskey"
        case .whiteRum: return "White Rum"
        case .agedRum: return "Aged Rum"
        case .darkRum: return "Dark Rum"
        case .agricole: return "Agricole"
        case .otherRum: return "Other Rum"
        case .tequila: return "Tequila"
        case .mezcal: return "Mezcal"
        case .otherAgave: return "Other Agave"
        case .cognac: return "Cognac"
        case .armagnac: return "Armagnac"
        case .pisco: return "Pisco"
        case .calvados: return "Calvados"
        case .otherBrandy: return "Other Brandy"
        }
    }

    static func guess(for name: String, in category: IngredientCategory) -> IngredientSubcategory? {
        let fallback: IngredientSubcategory
        switch category {
        case .whiskey: fallback = .otherWhiskey
        case .rum: fallback = .otherRum
        case .agave: fallback = .otherAgave
        case .brandy: fallback = .otherBrandy
        default: return nil
        }
        let text = IngredientKey.normalized(name)
        for (subcategory, pattern) in rules where subcategory.category == category
            && text.range(of: pattern, options: .regularExpression) != nil {
            return subcategory
        }
        return fallback
    }

    /// Checked in order: the style named outright first, so "Knob Creek Rye" is rye and
    /// "high-rye bourbon" is bourbon; well-known brands only after that.
    private static let rules: [(IngredientSubcategory, String)] = [
        (.bourbon, ["bourbon"]),
        (.rye, ["rye"]),
        (.scotch, ["scotch", "islay", "speyside", "single malt", "blended malt"]),
        (.irish, ["irish"]),
        (.japanese, ["japanese"]),
        (.bourbon, ["maker's mark", "makers mark", "buffalo trace", "woodford", "wild turkey", "knob creek",
                    "four roses", "elijah craig", "old forester", "evan williams", "eagle rare", "basil hayden"]),
        (.rye, ["rittenhouse", "pikesville", "sazerac"]),
        (.scotch, ["laphroaig", "lagavulin", "ardbeg", "talisker", "glenlivet", "glenfiddich", "macallan",
                   "monkey shoulder", "johnnie walker", "dewar's", "famous grouse", "highland park"]),
        (.irish, ["jameson", "redbreast", "bushmills", "powers", "teeling", "tullamore"]),
        (.japanese, ["suntory", "nikka", "hibiki", "yamazaki", "hakushu"]),
        (.agricole, ["agricole", "rhum"]),
        (.darkRum, ["dark", "black", "navy", "blackstrap", "gosling's", "goslings"]),
        (.agedRum, ["aged", "añejo", "anejo", "gold", "reserva", "extra old"]),
        (.whiteRum, ["white", "blanco", "silver", "light", "plata"]),
        (.mezcal, ["mezcal", "espadín", "espadin"]),
        (.tequila, ["tequila", "blanco", "reposado", "añejo", "anejo", "plata"]),
        (.cognac, ["cognac", "hennessy", "rémy martin", "remy martin", "pierre ferrand", "courvoisier"]),
        (.armagnac, ["armagnac"]),
        (.pisco, ["pisco"]),
        (.calvados, ["calvados"]),
    ].map { subcategory, words in (subcategory, IngredientCategory.wordPattern(words)) }
}

/// Where an ingredient is filed: a category, plus a subcategory for the main spirits.
struct IngredientKind: Hashable {
    var category: IngredientCategory
    var subcategory: IngredientSubcategory?

    var title: String { subcategory?.title ?? category.title }

    static func guess(for name: String) -> IngredientKind {
        let category = IngredientCategory.guess(for: name)
        return IngredientKind(category: category, subcategory: IngredientSubcategory.guess(for: name, in: category))
    }

    /// Whether a drink ingredient of `kind` counts for this one as a filter: a whole
    /// category (no subcategory) takes in all its subcategories.
    func includes(_ kind: IngredientKind) -> Bool {
        kind.category == category && (subcategory == nil || kind.subcategory == subcategory)
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
    var subcategoryRaw: String?

    init(key: String, kind: IngredientKind) {
        self.key = key
        self.categoryRaw = kind.category.rawValue
        self.subcategoryRaw = kind.subcategory?.rawValue
    }

    var kind: IngredientKind {
        get {
            let category = IngredientCategory(rawValue: categoryRaw) ?? .uncategorized
            // Choices saved before subcategories existed fall back to the guess within their category.
            let subcategory = subcategoryRaw.flatMap(IngredientSubcategory.init(rawValue:))
                ?? IngredientSubcategory.guess(for: key, in: category)
            return IngredientKind(category: category, subcategory: subcategory)
        }
        set {
            categoryRaw = newValue.category.rawValue
            subcategoryRaw = newValue.subcategory?.rawValue
        }
    }
}
