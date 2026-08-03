import SwiftUI
import UIKit

struct CocktailRowView: View {
    let cocktail: Cocktail

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            thumbnail
            VStack(alignment: .leading, spacing: 4) {
                Text(cocktail.displayTitle)
                    .font(.headline)
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)

                if !cocktail.ingredientSummary.isEmpty {
                    Text(cocktail.ingredientSummary)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1)
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

                Text(cocktail.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(AppTheme.tertiaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let data = cocktail.photoData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.photoPlaceholder)
                .frame(width: 64, height: 64)
                .overlay {
                    Image(systemName: "wineglass.fill")
                        .foregroundStyle(AppTheme.accent.opacity(0.7))
                }
        }
    }
}
