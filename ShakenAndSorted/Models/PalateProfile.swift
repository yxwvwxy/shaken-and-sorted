import Foundation

/// What your ratings say about your taste. Each rated drink counts as a score
/// (Nuh uh −2, Meh −0.5, Not bad +1, Love it +2) for the flavors, spirits and
/// ingredients in it.
struct PalateProfile {
    static let unlockCount = 5

    let ratedCount: Int
    /// Average score per flavor, or nil when no rated drink has it.
    let flavors: [(flavor: Flavor, score: Double?, drinks: Int)]
    let spirits: [Affinity]
    let favorites: [Affinity]
    let dislikes: [Affinity]
    let picks: [(recipe: Cocktail, score: Double)]

    var isUnlocked: Bool { ratedCount >= Self.unlockCount }

    struct Affinity: Identifiable {
        let title: String
        let score: Double
        let drinks: Int
        var id: String { title }
    }

    enum Flavor: String, CaseIterable, Identifiable {
        case sweet, sour, bitter, boozy, herbal, fruity, smoky, creamy

        var id: String { rawValue }

        var title: String {
            switch self {
            case .sweet: return "Sweet"
            case .sour: return "Sour"
            case .bitter: return "Bitter"
            case .boozy: return "Boozy"
            case .herbal: return "Herbal"
            case .fruity: return "Fruity"
            case .smoky: return "Smoky"
            case .creamy: return "Creamy"
            }
        }
    }

    static func score(for rating: DrinkRating) -> Double {
        switch rating {
        case .notForMe: return -2
        case .meh: return -0.5
        case .notBad: return 1
        case .loveIt: return 2
        }
    }

    init(drinks: [Cocktail], recipes: [Cocktail], catalog: IngredientCatalog) {
        let rated = drinks.compactMap { drink in drink.drinkRating.map { (drink, Self.score(for: $0)) } }
        ratedCount = rated.count

        var flavorScores: [Flavor: [Double]] = [:]
        var spiritScores: [IngredientKind: [Double]] = [:]
        var ingredientScores: [String: (name: String, scores: [Double])] = [:]
        var kindScores: [IngredientKind: [Double]] = [:]

        for (drink, score) in rated {
            let names = drink.cleanedIngredients
            let kinds = names.map(catalog.kind(of:))
            for flavor in Self.flavors(names: names, kinds: kinds) {
                flavorScores[flavor, default: []].append(score)
            }
            // Each spirit kind and ingredient counts once per drink.
            for kind in Set(kinds) {
                kindScores[kind, default: []].append(score)
                if kind.category.isSpirit {
                    spiritScores[kind, default: []].append(score)
                }
            }
            for name in Set(names) {
                let key = IngredientKey.normalized(name)
                ingredientScores[key, default: (name, [])].scores.append(score)
            }
        }

        flavors = Flavor.allCases.map { flavor in
            let scores = flavorScores[flavor] ?? []
            return (flavor, scores.isEmpty ? nil : scores.average, scores.count)
        }

        spirits = spiritScores
            .map { kind, scores in
                Affinity(title: kind.title, score: scores.average, drinks: scores.count)
            }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.drinks > $1.drinks }

        let ingredients = ingredientScores.map { key, value in
            Affinity(title: value.name, score: value.scores.average, drinks: value.scores.count)
        }
        favorites = Array(ingredients.filter { $0.score >= 1 }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.drinks > $1.drinks }
            .prefix(5))
        dislikes = Array(ingredients.filter { $0.score < 0 }
            .sorted { $0.score != $1.score ? $0.score < $1.score : $0.drinks > $1.drinks }
            .prefix(5))

        // A recipe scores by what you thought of its ingredients, or of their kind when the
        // exact ingredient is new to you.
        let ingredientAverages = ingredientScores.mapValues { $0.scores.average }
        let kindAverages = kindScores.mapValues(\.average)
        picks = Array(recipes
            .compactMap { recipe -> (Cocktail, Double)? in
                let known = recipe.cleanedIngredients.compactMap { name -> Double? in
                    ingredientAverages[IngredientKey.normalized(name)]
                        ?? kindAverages[catalog.kind(of: name)]
                        ?? kindAverages[IngredientKind(category: catalog.kind(of: name).category)]
                }
                guard !known.isEmpty else { return nil }
                let score = known.average
                return score > 0 ? (recipe, score) : nil
            }
            .sorted { $0.1 > $1.1 }
            .prefix(3))
            .map { (recipe: $0.0, score: $0.1) }
    }

    /// The flavors a drink has, from its ingredients' kinds and names. A drink with
    /// spirit but nothing sour, juicy or bubbly counts as boozy.
    static func flavors(names: [String], kinds: [IngredientKind]) -> Set<Flavor> {
        var found: Set<Flavor> = []
        let text = names.map { IngredientKey.normalized($0) }.joined(separator: " | ")
        func has(_ words: [String]) -> Bool {
            words.contains { text.range(of: "(?<![a-z])\($0)", options: .regularExpression) != nil }
        }

        for kind in kinds {
            switch kind.category {
            case .sweeteners, .liqueurs: found.insert(.sweet)
            case .citrus: found.insert(.sour)
            case .bitters: found.insert(.bitter)
            case .juicesAndFresh: found.insert(.fruity)
            case .texture: found.insert(.creamy)
            case .gin: found.insert(.herbal)
            case .aperitifs: found.insert(.herbal)
            default: break
            }
            if kind.subcategory == .mezcal { found.insert(.smoky) }
        }
        if has(["campari", "aperol", "amaro", "fernet", "cynar", "suze", "averna", "montenegro", "nonino", "bitter"]) {
            found.insert(.bitter)
        }
        if has(["chartreuse", "absinthe", "bénédictine", "benedictine", "mint", "basil", "rosemary", "thyme", "sage", "genepy", "vermouth"]) {
            found.insert(.herbal)
        }
        if has(["mezcal", "islay", "laphroaig", "lagavulin", "ardbeg", "smoked", "smoky", "peat"]) {
            found.insert(.smoky)
        }
        if has(["cherry", "berry", "peach", "apple", "pear", "passion", "mango", "pineapple", "banana", "cassis", "framboise", "orange liqueur", "curaçao", "curacao", "cointreau", "triple sec", "maraschino"]) {
            found.insert(.fruity)
        }
        if has(["coconut", "egg", "cream", "milk", "butter"]) {
            found.insert(.creamy)
        }

        let hasSpirit = kinds.contains { $0.category.isSpirit }
        let isLengthened = kinds.contains { [.citrus, .juicesAndFresh, .mixers].contains($0.category) }
        if hasSpirit, !isLengthened { found.insert(.boozy) }
        return found
    }
}

extension IngredientCategory {
    var isSpirit: Bool {
        [.whiskey, .gin, .vodka, .rum, .agave, .brandy, .otherSpirits].contains(self)
    }
}

private extension Array where Element == Double {
    var average: Double { isEmpty ? 0 : reduce(0, +) / Double(count) }
}
