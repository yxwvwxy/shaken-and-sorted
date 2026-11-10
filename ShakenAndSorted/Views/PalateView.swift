import SwiftUI
import SwiftData

/// The palate card: progress toward unlocking, then a way into the profile.
struct PalateCard: View {
    let profile: PalateProfile

    var body: some View {
        if profile.isUnlocked {
            NavigationLink {
                PalateView()
            } label: {
                label(subtitle: "From \(profile.ratedCount) rated drinks")
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                let remaining = PalateProfile.unlockCount - profile.ratedCount
                label(subtitle: remaining == 1 ? "Rate 1 more drink to unlock" : "Rate \(remaining) more drinks to unlock")
                ProgressView(value: Double(profile.ratedCount), total: Double(PalateProfile.unlockCount))
                    .tint(AppTheme.accent)
                Text("\(profile.ratedCount) / \(PalateProfile.unlockCount) rated")
                    .font(.caption)
                    .foregroundStyle(AppTheme.tertiaryText)
            }
            .padding(.vertical, 4)
        }
    }

    private func label(subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: profile.isUnlocked ? "sparkles" : "lock")
                .font(.title2)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("Your Palate")
                    .font(.headline)
                    .foregroundStyle(AppTheme.primaryText)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Flavor radar, favorite spirits and ingredients, ones to skip, and recipes to try next.
struct PalateView: View {
    @Environment(DrinkFilter.self) private var drinkFilter
    @Query(filter: Cocktail.loggedDrinks) private var drinks: [Cocktail]
    @Query(filter: Cocktail.recipes) private var recipes: [Cocktail]
    @Query private var choices: [IngredientCategoryChoice]

    private var profile: PalateProfile {
        PalateProfile(
            drinks: drinks,
            recipes: recipes,
            catalog: IngredientCatalog(cocktails: drinks, choices: choices)
        )
    }

    var body: some View {
        let profile = profile
        List {
            Section {
                FlavorRadar(flavors: profile.flavors)
                    .frame(height: 300)
                    .padding(.vertical, 8)
            } header: {
                Text("Flavors")
            } footer: {
                Text("Further out means you rated drinks with that flavor higher. Grey ones have no rated drinks yet.")
            }
            .listRowBackground(AppTheme.card)

            if !profile.spirits.isEmpty {
                Section("Spirits") {
                    ForEach(profile.spirits) { spirit in
                        AffinityRow(affinity: spirit)
                    }
                }
                .listRowBackground(AppTheme.card)
            }

            if !profile.favorites.isEmpty {
                Section("You Love") {
                    ForEach(profile.favorites) { AffinityRow(affinity: $0) }
                }
                .listRowBackground(AppTheme.card)
            }

            if !profile.dislikes.isEmpty {
                Section("Not for You") {
                    ForEach(profile.dislikes) { AffinityRow(affinity: $0) }
                }
                .listRowBackground(AppTheme.card)
            }

            Section {
                if profile.picks.isEmpty {
                    Text("Save some recipes and the ones that suit you best show up here.")
                        .foregroundStyle(AppTheme.secondaryText)
                } else {
                    ForEach(profile.picks, id: \.recipe.id) { pick in
                        Button {
                            drinkFilter.openRecipe(pick.recipe)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pick.recipe.displayTitle)
                                        .foregroundStyle(AppTheme.primaryText)
                                    Text(pick.recipe.cleanedIngredients.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.secondaryText)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.tertiaryText)
                            }
                        }
                    }
                }
            } header: {
                Text("Try Next")
            } footer: {
                Text("From your Recipes, by how you rated their ingredients.")
            }
            .listRowBackground(AppTheme.card)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Your Palate")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AffinityRow: View {
    let affinity: PalateProfile.Affinity

    var body: some View {
        HStack(spacing: 12) {
            Text(affinity.title)
                .foregroundStyle(AppTheme.primaryText)
            Spacer()
            ScoreBar(score: affinity.score)
                .frame(width: 90, height: 8)
            Text(affinity.drinks == 1 ? "1 drink" : "\(affinity.drinks) drinks")
                .font(.caption)
                .foregroundStyle(AppTheme.tertiaryText)
                .frame(width: 52, alignment: .trailing)
        }
    }
}

/// A bar from the middle: right and green for liked, left and red for not.
private struct ScoreBar: View {
    let score: Double

    var body: some View {
        GeometryReader { geo in
            let half = geo.size.width / 2
            let length = half * min(abs(score) / 2, 1)
            ZStack(alignment: .leading) {
                Capsule().fill(AppTheme.photoPlaceholder)
                Rectangle()
                    .fill(score >= 0 ? DrinkRating.loveIt.color : DrinkRating.notForMe.color)
                    .frame(width: length)
                    .offset(x: score >= 0 ? half : half - length)
                Rectangle()
                    .fill(AppTheme.tertiaryText)
                    .frame(width: 1)
                    .offset(x: half)
            }
            .clipShape(Capsule())
        }
    }
}

/// Eight flavors around a circle; each point sits further out the better you rated it.
private struct FlavorRadar: View {
    let flavors: [(flavor: PalateProfile.Flavor, score: Double?, drinks: Int)]

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = min(geo.size.width, geo.size.height) / 2 - 36
            ZStack {
                ForEach(1...4, id: \.self) { ring in
                    polygon(values: Array(repeating: Double(ring) / 4, count: flavors.count), center: center, radius: radius)
                        .stroke(AppTheme.photoPlaceholder, lineWidth: 1)
                }
                ForEach(Array(flavors.enumerated()), id: \.offset) { index, _ in
                    Path { path in
                        path.move(to: center)
                        path.addLine(to: point(index: index, value: 1, center: center, radius: radius))
                    }
                    .stroke(AppTheme.photoPlaceholder, lineWidth: 1)
                }
                let values = flavors.map { ($0.score.map { ($0 + 2) / 4 }) ?? 0 }
                polygon(values: values, center: center, radius: radius)
                    .fill(AppTheme.accent.opacity(0.15))
                polygon(values: values, center: center, radius: radius)
                    .stroke(AppTheme.accent, lineWidth: 2)
                ForEach(Array(flavors.enumerated()), id: \.offset) { index, item in
                    let spot = point(index: index, value: 1.22, center: center, radius: radius)
                    Text(item.flavor.title)
                        .font(.caption.weight(.semibold))
                    .foregroundStyle(item.score == nil ? AppTheme.tertiaryText : AppTheme.primaryText)
                    .position(spot)
                }
            }
        }
    }

    private func point(index: Int, value: Double, center: CGPoint, radius: CGFloat) -> CGPoint {
        let angle = Double(index) / Double(flavors.count) * 2 * .pi - .pi / 2
        return CGPoint(
            x: center.x + CGFloat(cos(angle) * value) * radius,
            y: center.y + CGFloat(sin(angle) * value) * radius
        )
    }

    private func polygon(values: [Double], center: CGPoint, radius: CGFloat) -> Path {
        Path { path in
            for (index, value) in values.enumerated() {
                let spot = point(index: index, value: max(value, 0.02), center: center, radius: radius)
                if index == 0 { path.move(to: spot) } else { path.addLine(to: spot) }
            }
            path.closeSubpath()
        }
    }
}
