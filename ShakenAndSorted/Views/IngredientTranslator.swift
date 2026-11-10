import SwiftUI
import SwiftData
import Translation

extension View {
    /// Translates ingredient names that have no Chinese yet, on the phone with Apple's
    /// translation (iOS 18 and later). The first time, iOS may ask to download Chinese.
    @ViewBuilder
    func translatesToChinese(_ pending: [PendingTranslation]) -> some View {
        if #available(iOS 18.0, *) {
            modifier(IngredientTranslator(pending: pending))
        } else {
            self
        }
    }
}

/// An ingredient name, and the key its Chinese is stored under.
struct PendingTranslation: Equatable {
    let key: String
    let name: String
}

/// Watches every ingredient in drinks and recipes and gives the new ones a Chinese name:
/// from the cocktail glossary when it knows the words, otherwise Apple's translation.
/// Automatic names are kept up to date with the glossary; hand-typed ones are never touched.
struct IngredientTranslationWatcher: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    @Query private var cocktails: [Cocktail]
    @Query private var translations: [IngredientTranslation]

    func body(content: Content) -> some View {
        content
            .translatesToChinese(needsGeneralTranslation)
            .onChange(of: allIngredients.map(\.key), initial: true) {
                applyGlossary()
            }
    }

    private var allIngredients: [PendingTranslation] {
        var seen: Set<String> = []
        var result: [PendingTranslation] = []
        for cocktail in cocktails {
            for name in cocktail.cleanedIngredients {
                let key = IngredientKey.normalized(name)
                if seen.insert(key).inserted {
                    result.append(PendingTranslation(key: key, name: name))
                }
            }
        }
        return result
    }

    /// Not yet named, and not something the glossary can name.
    private var needsGeneralTranslation: [PendingTranslation] {
        let known = Set(translations.map(\.key))
        return allIngredients.filter { !known.contains($0.key) && CocktailGlossary.chinese(for: $0.name) == nil }
    }

    private func applyGlossary() {
        let existing = Dictionary(translations.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        var changed = false
        for ingredient in allIngredients {
            guard let chinese = CocktailGlossary.chinese(for: ingredient.name) else { continue }
            if let saved = existing[ingredient.key] {
                if !saved.isManual, saved.chinese != chinese {
                    saved.chinese = chinese
                    changed = true
                }
            } else {
                modelContext.insert(IngredientTranslation(key: ingredient.key, chinese: chinese))
                changed = true
            }
        }
        if changed { try? modelContext.save() }
    }
}

@available(iOS 18.0, *)
private struct IngredientTranslator: ViewModifier {
    let pending: [PendingTranslation]
    @Environment(\.modelContext) private var modelContext
    @State private var configuration: TranslationSession.Configuration?

    func body(content: Content) -> some View {
        content
            .translationTask(configuration) { session in
                let requests = pending.map {
                    TranslationSession.Request(sourceText: $0.name, clientIdentifier: $0.key)
                }
                guard !requests.isEmpty else { return }
                let responses: [TranslationSession.Response]
                do {
                    try await session.prepareTranslation()
                    responses = try await session.translations(from: requests)
                } catch {
                    // Usually the Chinese language pack isn't downloaded yet; tried again next time.
                    return
                }
                await MainActor.run {
                    for response in responses {
                        guard let key = response.clientIdentifier else { continue }
                        let chinese = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !chinese.isEmpty else { continue }
                        modelContext.insert(IngredientTranslation(key: key, chinese: chinese))
                    }
                    try? modelContext.save()
                }
            }
            .onChange(of: pending.map(\.key), initial: true) { _, keys in
                guard !keys.isEmpty else { return }
                if configuration == nil {
                    configuration = .init(
                        source: Locale.Language(identifier: "en"),
                        target: Locale.Language(identifier: "zh-Hans")
                    )
                } else {
                    configuration?.invalidate()
                }
            }
    }
}
