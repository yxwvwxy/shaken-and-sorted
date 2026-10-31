import Foundation
import SwiftUI
import UIKit
import Vision

struct MenuRecognitionResult: Equatable {
    var name: String
    var ingredients: [String]
    var price: String = ""

    var cleanedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var cleanedIngredients: [String] {
        ingredients
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var cleanedPrice: String {
        price.trimmingCharacters(in: CharacterSet(charactersIn: ",;").union(.whitespacesAndNewlines))
    }

    var hasAnything: Bool {
        !cleanedName.isEmpty || !cleanedIngredients.isEmpty || !cleanedPrice.isEmpty
    }
}

enum MenuRecognitionError: LocalizedError {
    case unreadableImage
    case noText
    case nothingHighlighted

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            return "Could not read that photo. Try another one."
        case .noText:
            return "No text found in this photo. Try a clearer, closer shot of the menu."
        case .nothingHighlighted:
            return "Highlight the drink's name, ingredients, or price first."
        }
    }
}

/// One word on the menu photo, as found by on-device text recognition.
struct MenuWord: Identifiable {
    let id: Int
    let text: String
    /// Whether the printed text has a space (or a line break) before this word.
    /// False inside "Single-Barrel" and between Chinese or Japanese words.
    let spaceBefore: Bool
    /// Normalized to the photo, origin top-left.
    let box: CGRect
}

enum HighlightMode: CaseIterable {
    case name
    case ingredients
    case price

    var title: String {
        switch self {
        case .name: return "Name"
        case .ingredients: return "Ingredients"
        case .price: return "Price"
        }
    }

    var color: UIColor {
        switch self {
        case .name: return .systemYellow
        case .ingredients: return .systemGreen
        case .price: return .systemPink
        }
    }
}

struct HighlightStroke {
    var mode: HighlightMode
    /// Canvas coordinates (unzoomed).
    var points: [CGPoint]
    /// Pen width in canvas coordinates; thinner when drawn zoomed in.
    var width: CGFloat
}

/// Reads all text on the menu photo once, fully on device (Vision). No network, no API key.
enum MenuTextReader {
    static func words(in image: UIImage) async throws -> [MenuWord] {
        guard let cgImage = image.normalizedUp().cgImage else {
            throw MenuRecognitionError.unreadableImage
        }

        let observations: [VNRecognizedTextObservation] = try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (request.results as? [VNRecognizedTextObservation]) ?? [])
                }
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

        // Reading order: top to bottom, then left to right.
        let lines = observations.sorted {
            let dy = $0.boundingBox.midY - $1.boundingBox.midY
            if abs(dy) > 0.01 { return dy > 0 }
            return $0.boundingBox.minX < $1.boundingBox.minX
        }

        var words: [MenuWord] = []
        for line in lines {
            guard let candidate = line.topCandidates(1).first else { continue }
            let text = candidate.string
            for range in tokenRanges(in: text) {
                guard let box = try? candidate.boundingBox(for: range)?.boundingBox else { continue }
                let spaceBefore = range.lowerBound == text.startIndex
                    || text[text.index(before: range.lowerBound)].isWhitespace
                words.append(MenuWord(
                    id: words.count,
                    text: String(text[range]),
                    spaceBefore: spaceBefore,
                    box: CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
                ))
            }
        }
        return words
    }

    /// Words with the punctuation stuck to them ("Rye," / "“The"), so commas
    /// survive for splitting ingredients. Uses word segmentation so Chinese and
    /// Japanese, which have no spaces, still split into words.
    private static func tokenRanges(in text: String) -> [Range<String.Index>] {
        var wordRanges: [Range<String.Index>] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byWords) { _, range, _, _ in
            wordRanges.append(range)
        }

        var tokens: [Range<String.Index>] = []
        var previousEnd = text.startIndex
        for (index, range) in wordRanges.enumerated() {
            var start = range.lowerBound
            while start > previousEnd, !text[text.index(before: start)].isWhitespace {
                start = text.index(before: start)
            }
            let limit = index + 1 < wordRanges.count ? wordRanges[index + 1].lowerBound : text.endIndex
            var end = range.upperBound
            while end < limit, !text[end].isWhitespace {
                end = text.index(after: end)
            }
            tokens.append(start..<end)
            previousEnd = end
        }
        return tokens
    }
}

/// Turns highlighter strokes into a drink: the words each stroke passes over.
enum MenuHighlightReader {
    /// Which stroke (by index) picked each word. A word goes to the first stroke that touches it.
    static func assignments(words: [MenuWord], strokes: [HighlightStroke], fit: CGRect) -> [Int: Int] {
        var picked: [Int: Int] = [:]
        for (strokeIndex, stroke) in strokes.enumerated() {
            let samples = densePoints(stroke.points, step: 2)
            guard let first = samples.first else { continue }
            let reach = stroke.width * 0.3
            let bounds = samples.reduce(CGRect(origin: first, size: .zero)) {
                $0.union(CGRect(origin: $1, size: .zero))
            }.insetBy(dx: -reach, dy: -reach)

            for word in words where picked[word.id] == nil {
                let rect = canvasRect(for: word, fit: fit)
                guard rect.intersects(bounds) else { continue }
                if samples.contains(where: { distance(from: $0, to: rect) <= reach }) {
                    picked[word.id] = strokeIndex
                }
            }
        }
        return picked
    }

    static func result(words: [MenuWord], strokes: [HighlightStroke], fit: CGRect) -> MenuRecognitionResult {
        let picked = assignments(words: words, strokes: strokes, fit: fit)

        func highlighted(_ mode: HighlightMode) -> [MenuWord] {
            words.filter { word in picked[word.id].map { strokes[$0].mode == mode } ?? false }
        }
        let name = stripPrice(joined(highlighted(.name)))
        let price = joined(highlighted(.price))

        // One group per ingredient stroke, in reading order of where each starts.
        var groups: [Int: [MenuWord]] = [:]
        for word in words {
            guard let strokeIndex = picked[word.id], strokes[strokeIndex].mode == .ingredients else { continue }
            groups[strokeIndex, default: []].append(word)
        }
        let ingredients = groups.values
            .sorted { ($0.first?.id ?? 0) < ($1.first?.id ?? 0) }
            .flatMap { splitIngredients(joined($0)) }

        return MenuRecognitionResult(name: name, ingredients: ingredients, price: price)
    }

    static func canvasRect(for word: MenuWord, fit: CGRect) -> CGRect {
        CGRect(
            x: fit.minX + word.box.minX * fit.width,
            y: fit.minY + word.box.minY * fit.height,
            width: word.box.width * fit.width,
            height: word.box.height * fit.height
        )
    }

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

    /// Joins words the way they were printed: spaced, except inside "Single-Barrel" or Chinese text.
    static func joined(_ words: [MenuWord]) -> String {
        words.reduce(into: "") { text, word in
            if !text.isEmpty, word.spaceBefore { text += " " }
            text += word.text
        }
    }

    /// Splits a highlighted run like "Rye, Yellow Chartreuse & Orange Bitters" into items.
    static func splitIngredients(_ text: String) -> [String] {
        let separators: Set<Character> = [",", "，", "、", "·", "•", "/", "|", ";", "；", "&"]
        return text
            .split(whereSeparator: { separators.contains($0) })
            .map { piece in
                // Commas inside quoted names leave stray quote marks behind; drop them.
                var item = stripPrice(String(piece))
                    .filter { !"“”\"".contains($0) }
                    .trimmingCharacters(in: CharacterSet(charactersIn: "*.").union(.whitespaces))
                for joiner in ["or ", "and "] where item.lowercased().hasPrefix(joiner) {
                    item = String(item.dropFirst(joiner.count))
                }
                return item
            }
            .filter { $0.contains(where: \.isLetter) }
    }

    private static func stripPrice(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"\s*[\$¥€£]?\s*\d+([.,]\d+)?\s*[\$¥€£元]?\s*$"#,
            with: "",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func densePoints(_ points: [CGPoint], step: CGFloat) -> [CGPoint] {
        guard var previous = points.first else { return [] }
        var result = [previous]
        for point in points.dropFirst() {
            let length = hypot(point.x - previous.x, point.y - previous.y)
            let count = max(1, Int(length / step))
            for i in 1...count {
                let t = CGFloat(i) / CGFloat(count)
                result.append(CGPoint(x: previous.x + (point.x - previous.x) * t, y: previous.y + (point.y - previous.y) * t))
            }
            previous = point
        }
        return result
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
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
