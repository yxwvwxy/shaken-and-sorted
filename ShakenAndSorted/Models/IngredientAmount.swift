import Foundation

/// How amounts are shown. Saved amounts are never changed; conversion is display only.
enum AmountDisplay: String, CaseIterable, Identifiable {
    case asWritten
    case oz
    case ml

    var id: String { rawValue }

    var title: String {
        switch self {
        case .asWritten: return "As Written"
        case .oz: return "oz"
        case .ml: return "ml"
        }
    }
}

/// Reads and converts bar amounts like "1½ oz", "3/4 oz", "45 ml", "2 cl".
/// Uses the bar convention 1 oz = 30 ml. Anything else ("2 dashes", "top") is left alone.
enum IngredientAmount {
    /// Unit shortcuts offered while typing an amount.
    static let quickUnits = ["oz", "ml", "cl", "dash", "drop", "bar spoon", "tsp", "piece", "top", "rinse"]

    static let mlPerOz: Double = 30

    /// Whether the amount is in oz, ml or cl, so it can be shown in another unit.
    static func canConvert(_ amount: String) -> Bool {
        parse(amount) != nil
    }

    static func display(_ amount: String, as display: AmountDisplay) -> String {
        guard display != .asWritten, let parsed = parse(amount) else { return amount }
        let ml = parsed.ml
        switch display {
        case .asWritten:
            return amount
        case .oz:
            return parsed.unit == .oz ? amount : "\(fractionText(ml / mlPerOz)) oz\(parsed.rest)"
        case .ml:
            return parsed.unit == .ml ? amount : "\(decimalText(ml)) ml\(parsed.rest)"
        }
    }

    private enum Unit {
        case oz, ml, cl
    }

    private struct Parsed {
        var value: Double
        var unit: Unit
        /// Words after the unit, kept as printed (" each").
        var rest: String

        var ml: Double {
            switch unit {
            case .oz: return value * IngredientAmount.mlPerOz
            case .ml: return value
            case .cl: return value * 10
            }
        }
    }

    private static let vulgarFractions: [Character: Double] = [
        "¼": 0.25, "½": 0.5, "¾": 0.75, "⅓": 1.0 / 3, "⅔": 2.0 / 3, "⅛": 0.125, "⅜": 0.375, "⅝": 0.625, "⅞": 0.875
    ]

    private static let pattern = try? NSRegularExpression(
        pattern: #"^\s*(\d+(?:\.\d+)?|\.\d+)?\s*(?:(\d+)\s*/\s*(\d+)|([¼½¾⅓⅔⅛⅜⅝⅞]))?\s*(fl\.?\s*oz|oz|ounces?|ml|cl)(?![a-z])(.*)$"#,
        options: .caseInsensitive
    )

    private static func parse(_ amount: String) -> Parsed? {
        let text = amount as NSString
        guard let pattern,
              let match = pattern.firstMatch(in: amount, range: NSRange(location: 0, length: text.length))
        else { return nil }

        func group(_ index: Int) -> String? {
            let range = match.range(at: index)
            return range.location == NSNotFound ? nil : text.substring(with: range)
        }

        var value = group(1).flatMap(Double.init) ?? 0
        if let numerator = group(2).flatMap(Double.init), let denominator = group(3).flatMap(Double.init), denominator > 0 {
            value += numerator / denominator
        }
        if let symbol = group(4)?.first, let fraction = vulgarFractions[symbol] {
            value += fraction
        }
        guard value > 0, let unitText = group(5)?.lowercased() else { return nil }

        let unit: Unit
        if unitText.hasPrefix("ml") {
            unit = .ml
        } else if unitText.hasPrefix("cl") {
            unit = .cl
        } else {
            unit = .oz
        }
        return Parsed(value: value, unit: unit, rest: group(6) ?? "")
    }

    /// Ounces to the nearest quarter, written the bar way: 0.75 → "¾", 1.5 → "1½".
    private static func fractionText(_ ounces: Double) -> String {
        let quarters = max(1, Int((ounces * 4).rounded()))
        let whole = quarters / 4
        let fraction = ["", "¼", "½", "¾"][quarters % 4]
        return whole == 0 ? fraction : "\(whole)\(fraction)"
    }

    /// Millilitres without a trailing ".0": 45 → "45", 22.5 → "22.5".
    private static func decimalText(_ ml: Double) -> String {
        let rounded = (ml * 2).rounded() / 2
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
    }
}
