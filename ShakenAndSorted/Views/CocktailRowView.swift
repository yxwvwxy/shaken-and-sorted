import SwiftUI
import UIKit

struct CocktailRowView: View {
    let cocktail: Cocktail

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(cocktail.displayTitle)
                    .font(.headline)
                    .foregroundStyle(cocktail.hasName ? AppTheme.primaryText : AppTheme.tertiaryText)
                Spacer(minLength: 0)
                if let rating = cocktail.drinkRating {
                    RatingBadge(rating: rating)
                }
            }

            if !cocktail.cleanedIngredients.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(cocktail.cleanedIngredients.enumerated()), id: \.offset) { _, ingredient in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("•")
                            Text(ingredient)
                        }
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                    }
                }
            }

            Text(cocktail.createdAt.formatted(date: .abbreviated, time: .omitted))
                .font(.caption2)
                .foregroundStyle(AppTheme.tertiaryText)

            if cocktail.hasPlace, let place = cocktail.placeName {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(AppTheme.accent)
                    Text(place)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
            }

            if let data = cocktail.photoData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    // Fill mode overflows the frame; clipping hides that part but it still catches taps.
                    .allowsHitTesting(false)
            }
        }
        .padding(.vertical, 6)
    }
}

/// A rating as a small filled tag in its own color.
struct RatingBadge: View {
    let rating: DrinkRating

    var body: some View {
        Text(rating.title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(rating.textColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(rating.color, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

extension DrinkRating {
    /// Google Sheets' "light 3" pastels: light red, yellow, blue and green.
    var color: Color {
        switch self {
        case .notForMe: return Color(red: 0xF4 / 255, green: 0xCC / 255, blue: 0xCC / 255)
        case .meh: return Color(red: 0xFF / 255, green: 0xF2 / 255, blue: 0xCC / 255)
        case .notBad: return Color(red: 0xCF / 255, green: 0xE2 / 255, blue: 0xF3 / 255)
        case .loveIt: return Color(red: 0xD9 / 255, green: 0xEA / 255, blue: 0xD3 / 255)
        }
    }

    /// The pastels are light, so the text stays dark on all of them.
    var textColor: Color {
        AppTheme.primaryText
    }
}
