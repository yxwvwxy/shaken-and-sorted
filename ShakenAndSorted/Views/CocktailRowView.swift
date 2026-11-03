import SwiftUI
import UIKit

struct CocktailRowView: View {
    let cocktail: Cocktail

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if cocktail.hasName {
                Text(cocktail.trimmedName)
                    .font(.headline)
                    .foregroundStyle(AppTheme.primaryText)
            }

            if !cocktail.cleanedIngredients.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(cocktail.cleanedIngredients.enumerated()), id: \.offset) { _, ingredient in
                        Text(ingredient)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
            }

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

            Text(cocktail.createdAt.formatted(date: .abbreviated, time: .omitted))
                .font(.caption2)
                .foregroundStyle(AppTheme.tertiaryText)

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
