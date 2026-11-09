import SwiftUI
import SwiftData
import Translation

extension View {
    /// Translates ingredient names that have no Chinese yet, on the phone with Apple's
    /// translation (iOS 18 and later). The first time, iOS may ask to download Chinese.
    @ViewBuilder
    func translatesToChinese(_ pending: [IngredientEntry]) -> some View {
        if #available(iOS 18.0, *) {
            modifier(IngredientTranslator(pending: pending))
        } else {
            self
        }
    }
}

@available(iOS 18.0, *)
private struct IngredientTranslator: ViewModifier {
    let pending: [IngredientEntry]
    @Environment(\.modelContext) private var modelContext
    @State private var configuration: TranslationSession.Configuration?

    func body(content: Content) -> some View {
        content
            .translationTask(configuration) { session in
                let requests = pending.map {
                    TranslationSession.Request(sourceText: $0.name, clientIdentifier: $0.key)
                }
                guard !requests.isEmpty,
                      let responses = try? await session.translations(from: requests)
                else { return }
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
