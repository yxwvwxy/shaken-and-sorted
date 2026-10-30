import Foundation
import SwiftUI
import UIKit
import Vision
#if canImport(FoundationModels)
import FoundationModels
#endif

struct MenuRecognitionResult: Equatable {
    var name: String
    var ingredients: [String]

    var cleanedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var cleanedIngredients: [String] {
        ingredients
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var hasAnything: Bool {
        !cleanedName.isEmpty || !cleanedIngredients.isEmpty
    }
}

enum MenuRecognitionError: LocalizedError {
    case noCircle
    case cropFailed
    case emptyRead

    var errorDescription: String? {
        switch self {
        case .noCircle:
            return "Circle the drink on the menu first."
        case .cropFailed:
            return "Could not crop that circle. Try a slightly larger loop."
        case .emptyRead:
            return "Could not read a name or ingredients. Try a clearer photo or a tighter circle."
        }
    }
}

enum MenuCropper {
    static func aspectFitRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              container.width > 0, container.height > 0
        else { return .zero }

        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2
        )
        return CGRect(origin: origin, size: size)
    }

    static func crop(
        image: UIImage,
        path: Path,
        containerSize: CGSize,
        expand: CGFloat = 36
    ) -> UIImage? {
        let upright = image.normalizedUp()
        let fit = aspectFitRect(imageSize: upright.size, in: containerSize)
        guard fit.width > 1, fit.height > 1, !path.isEmpty else { return nil }

        var box = path.boundingRect.insetBy(dx: -expand, dy: -expand)
        box = box.intersection(fit)
        guard box.width > 12, box.height > 12 else { return nil }

        let imageBox = CGRect(
            x: (box.minX - fit.minX) / fit.width * upright.size.width,
            y: (box.minY - fit.minY) / fit.height * upright.size.height,
            width: box.width / fit.width * upright.size.width,
            height: box.height / fit.height * upright.size.height
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = upright.scale
        let renderer = UIGraphicsImageRenderer(size: imageBox.size, format: format)
        return renderer.image { _ in
            upright.draw(at: CGPoint(x: -imageBox.origin.x, y: -imageBox.origin.y))
        }
    }
}

/// Reads the circled drink fully on device: Vision OCR for the text, then
/// Apple's on-device language model (iOS 26+, Apple Intelligence) to pick out
/// the name and ingredients. Falls back to simple line rules when the model
/// is not available. No network, no API key, no cost.
enum MenuRecognizer {
    static func recognize(image: UIImage) async throws -> MenuRecognitionResult {
        let lines = try await readLines(in: image)
        guard !lines.isEmpty else { throw MenuRecognitionError.emptyRead }

        var result: MenuRecognitionResult?
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            result = await OnDeviceDrinkParser.parse(lines: lines)
        }
        #endif
        if result?.hasAnything != true {
            result = HeuristicDrinkParser.parse(lines: lines)
        }

        guard let result, result.hasAnything else { throw MenuRecognitionError.emptyRead }
        return MenuRecognitionResult(name: result.cleanedName, ingredients: result.cleanedIngredients)
    }

    /// Text lines in reading order (top to bottom, then left to right).
    private static func readLines(in image: UIImage) async throws -> [String] {
        guard let cgImage = image.normalizedUp().cgImage else {
            throw MenuRecognitionError.cropFailed
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines = observations
                    .sorted {
                        let dy = $0.boundingBox.midY - $1.boundingBox.midY
                        if abs(dy) > 0.02 { return dy > 0 }
                        return $0.boundingBox.minX < $1.boundingBox.minX
                    }
                    .compactMap { $0.topCandidates(1).first?.string }
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try VNImageRequestHandler(cgImage: cgImage).perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
private struct DrinkDraft {
    @Guide(description: "The cocktail title exactly as printed. Empty if none.")
    var name: String

    @Guide(description: "Ingredient names, one per item, in the original language. No prices, ABV, or descriptions.")
    var ingredients: [String]
}

@available(iOS 26.0, *)
private enum OnDeviceDrinkParser {
    static func parse(lines: [String]) async -> MenuRecognitionResult? {
        guard case .available = SystemLanguageModel.default.availability else { return nil }

        let session = LanguageModelSession(instructions: """
        You read OCR text from a cropped piece of a cocktail menu. The user circled one drink. \
        Text from the edges (prices, section titles, a neighboring drink) may be mixed in — ignore it. \
        Extract only the circled drink's name and ingredients. Do not invent anything that is not in the text.
        """)

        do {
            let response = try await session.respond(
                to: lines.joined(separator: "\n"),
                generating: DrinkDraft.self
            )
            return MenuRecognitionResult(name: response.content.name, ingredients: response.content.ingredients)
        } catch {
            return nil
        }
    }
}
#endif

/// Rule-based fallback: first real text line is the name, the rest is split
/// into ingredients on common menu separators.
enum HeuristicDrinkParser {
    static func parse(lines: [String]) -> MenuRecognitionResult {
        let useful = lines.filter { !isNoise($0) }
        guard let name = useful.first else {
            return MenuRecognitionResult(name: "", ingredients: [])
        }

        let separators: Set<Character> = [",", "，", "、", "·", "•", "/", "|", ";", "；"]
        let ingredients = useful.dropFirst()
            .flatMap { $0.split(whereSeparator: { separators.contains($0) }) }
            .map { stripPrice(String($0)) }
            .filter { !$0.isEmpty && !isNoise($0) }

        return MenuRecognitionResult(name: stripPrice(name), ingredients: ingredients)
    }

    /// Prices, ABV, and other lines without real letters.
    private static func isNoise(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.range(of: #"^[\$¥€£]?\s*\d+([.,]\d+)?\s*(%|abv|ml|oz|元|[\$¥€£])?$"#,
                         options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        return !trimmed.contains { $0.isLetter }
    }

    private static func stripPrice(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"\s*[\$¥€£]?\s*\d+([.,]\d+)?\s*[\$¥€£元]?\s*$"#,
            with: "",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension UIImage {
    func normalizedUp() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

}
