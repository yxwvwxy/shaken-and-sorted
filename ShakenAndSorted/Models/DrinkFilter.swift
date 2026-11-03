import Foundation
import Observation

/// Every ingredient across the logged drinks, merged by spelling, each filed under its
/// kind: the hand-picked one if there is one, otherwise the guess from its name.
struct IngredientCatalog {
    let entries: [IngredientEntry]
    private let picked: [String: IngredientKind]

    init(cocktails: [Cocktail], choices: [IngredientCategoryChoice]) {
        let picked = Dictionary(choices.map { ($0.key, $0.kind) }, uniquingKeysWith: { first, _ in first })
        var byKey: [String: IngredientEntry] = [:]
        var order: [String] = []
        for cocktail in cocktails {
            for name in cocktail.cleanedIngredients {
                let key = IngredientKey.normalized(name)
                if byKey[key] == nil {
                    // The first spelling seen is the one shown (cocktails come newest first).
                    byKey[key] = IngredientEntry(key: key, name: name, kind: picked[key] ?? .guess(for: name), cocktails: [])
                    order.append(key)
                }
                if byKey[key]?.cocktails.contains(where: { $0.id == cocktail.id }) == false {
                    byKey[key]?.cocktails.append(cocktail)
                }
            }
        }
        self.entries = order.compactMap { byKey[$0] }
        self.picked = picked
    }

    func kind(of ingredient: String) -> IngredientKind {
        picked[IngredientKey.normalized(ingredient)] ?? .guess(for: ingredient)
    }
}

struct IngredientEntry: Identifiable, Hashable {
    let key: String
    let name: String
    let kind: IngredientKind
    var cocktails: [Cocktail]

    var id: String { key }

    static func == (lhs: IngredientEntry, rhs: IngredientEntry) -> Bool { lhs.key == rhs.key }
    func hash(into hasher: inout Hasher) { hasher.combine(key) }
}

enum AppTab: Hashable {
    case drinks
    case recipes
    case ingredients
}

/// A condition picked from the Drinks search suggestions.
enum DrinkFilterToken: Hashable, Identifiable {
    /// A whole category ("Whiskey") or one subcategory ("Rye").
    case kind(IngredientKind)
    case ingredient(key: String, name: String)
    case drink(String)
    case place(String)

    var id: Self { self }

    var label: String {
        switch self {
        case .kind(let kind): return kind.title
        case .ingredient(_, let name): return name
        case .drink(let name): return name
        case .place(let name): return name
        }
    }

    var systemImage: String {
        switch self {
        case .kind: return "square.grid.2x2"
        case .ingredient: return "drop"
        case .drink: return "wineglass"
        case .place: return "mappin"
        }
    }
}

enum RatingOption: Hashable, CaseIterable, Identifiable {
    case loveIt, notBad, meh, nuhUh, unrated

    var id: Self { self }

    var rating: DrinkRating? {
        switch self {
        case .loveIt: return .loveIt
        case .notBad: return .notBad
        case .meh: return .meh
        case .nuhUh: return .notForMe
        case .unrated: return nil
        }
    }

    var title: String { rating?.title ?? "Unrated" }
}

enum DrinkSortOrder: Hashable, CaseIterable, Identifiable {
    case newest, oldest, rating

    var id: Self { self }

    var title: String {
        switch self {
        case .newest: return "Newest First"
        case .oldest: return "Oldest First"
        case .rating: return "Rating"
        }
    }
}

enum DateRange: Hashable, CaseIterable, Identifiable {
    case allTime, thisMonth, lastThreeMonths, thisYear

    var id: Self { self }

    var title: String {
        switch self {
        case .allTime: return "All Time"
        case .thisMonth: return "This Month"
        case .lastThreeMonths: return "Last 3 Months"
        case .thisYear: return "This Year"
        }
    }

    func contains(_ date: Date, now: Date = .now) -> Bool {
        let calendar = Calendar.current
        switch self {
        case .allTime:
            return true
        case .thisMonth:
            return calendar.isDate(date, equalTo: now, toGranularity: .month)
        case .lastThreeMonths:
            guard let start = calendar.date(byAdding: .month, value: -3, to: now) else { return true }
            return date >= start
        case .thisYear:
            return calendar.isDate(date, equalTo: now, toGranularity: .year)
        }
    }
}

/// Search, filters and sort for the Drinks list. Kept in memory only, so the app
/// always opens on every drink, newest first.
@Observable
final class DrinkFilter {
    var selectedTab: AppTab = .drinks
    var searchText = ""
    var tokens: [DrinkFilterToken] = []
    var ratings: Set<RatingOption> = []
    var dateRange: DateRange = .allTime
    var sort: DrinkSortOrder = .newest
    /// Drinks opened from the list; cleared to come back to the list itself.
    var drinksPath: [Cocktail] = []

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isFiltering: Bool {
        !tokens.isEmpty || !trimmedSearch.isEmpty || !ratings.isEmpty || dateRange != .allTime
    }

    /// Whether the filter sheet has anything set, for the toolbar icon.
    var hasSheetSettings: Bool {
        !ratings.isEmpty || dateRange != .allTime || sort != .newest
    }

    func clearFilters() {
        searchText = ""
        tokens = []
        ratings = []
        dateRange = .allTime
    }

    func resetSheet() {
        ratings = []
        dateRange = .allTime
        sort = .newest
    }

    /// Switches to the Drinks tab with this drink open.
    func open(_ cocktail: Cocktail) {
        clearFilters()
        drinksPath = [cocktail]
        selectedTab = .drinks
    }

    /// Switches to the Drinks tab showing only drinks with this ingredient.
    func showDrinks(with entry: IngredientEntry) {
        clearFilters()
        tokens = [.ingredient(key: entry.key, name: entry.name)]
        drinksPath = []
        selectedTab = .drinks
    }

    func apply(to cocktails: [Cocktail], catalog: IngredientCatalog) -> [Cocktail] {
        let query = trimmedSearch
        let matching = cocktails.filter { cocktail in
            guard dateRange.contains(cocktail.createdAt) else { return false }
            if !ratings.isEmpty {
                let option = ratings.first { $0.rating == cocktail.drinkRating }
                guard option != nil else { return false }
            }
            // Every picked condition must hold.
            for token in tokens where !matches(cocktail, token, catalog: catalog) {
                return false
            }
            if !query.isEmpty {
                let texts = [cocktail.name, cocktail.placeName ?? ""] + cocktail.cleanedIngredients
                guard texts.contains(where: { $0.localizedCaseInsensitiveContains(query) }) else { return false }
            }
            return true
        }
        return sorted(matching)
    }

    private func matches(_ cocktail: Cocktail, _ token: DrinkFilterToken, catalog: IngredientCatalog) -> Bool {
        switch token {
        case .kind(let kind):
            return cocktail.cleanedIngredients.contains { kind.includes(catalog.kind(of: $0)) }
        case .ingredient(let key, _):
            return cocktail.cleanedIngredients.contains { IngredientKey.normalized($0) == key }
        case .drink(let name):
            return cocktail.trimmedName.caseInsensitiveCompare(name) == .orderedSame
        case .place(let name):
            return (cocktail.placeName ?? "").caseInsensitiveCompare(name) == .orderedSame
        }
    }

    private func sorted(_ cocktails: [Cocktail]) -> [Cocktail] {
        switch sort {
        case .newest:
            return cocktails.sorted { $0.createdAt > $1.createdAt }
        case .oldest:
            return cocktails.sorted { $0.createdAt < $1.createdAt }
        case .rating:
            // Best first; equal ratings newest first; unrated last.
            return cocktails.sorted { lhs, rhs in
                let left = lhs.rating ?? 0
                let right = rhs.rating ?? 0
                return left != right ? left > right : lhs.createdAt > rhs.createdAt
            }
        }
    }
}
