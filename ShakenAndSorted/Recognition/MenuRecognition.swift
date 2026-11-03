import Foundation
import SwiftUI
import UIKit
import Vision

struct MenuRecognitionResult: Equatable {
    var name: String
    var ingredients: [String]
    var price: String = ""
    /// The menu photo that was scanned, as JPEG.
    var photoData: Data?

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
    /// Which printed line it is on, in reading order.
    let line: Int
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
        case .name: return .systemBlue
        case .ingredients: return .systemGreen
        case .price: return .systemYellow
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
        for (lineIndex, line) in lines.enumerated() {
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
                    line: lineIndex,
                    box: CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
                ))
            }
        }
        return words
    }

    /// Words with the punctuation stuck to them ("Rye," / "“The"), so commas
    /// survive for splitting ingredients. Lone marks between spaces ("&", "-") are
    /// tokens of their own. Word segmentation splits Chinese and Japanese, which
    /// have no spaces, and hyphenated words ("Single-" "Barrel").
    private static func tokenRanges(in text: String) -> [Range<String.Index>] {
        var tokens: [Range<String.Index>] = []
        var index = text.startIndex
        while index < text.endIndex {
            if text[index].isWhitespace {
                index = text.index(after: index)
                continue
            }
            let chunkStart = index
            while index < text.endIndex, !text[index].isWhitespace {
                index = text.index(after: index)
            }
            let chunk = chunkStart..<index

            var wordStarts: [String.Index] = []
            text.enumerateSubstrings(in: chunk, options: .byWords) { _, range, _, _ in
                wordStarts.append(range.lowerBound)
            }
            guard wordStarts.count > 1 else {
                tokens.append(chunk)
                continue
            }
            wordStarts[0] = chunkStart
            for (i, start) in wordStarts.enumerated() {
                let end = i + 1 < wordStarts.count ? wordStarts[i + 1] : chunk.upperBound
                tokens.append(start..<end)
            }
        }
        return tokens
    }
}

/// Turns highlighter strokes into a drink: the words each stroke passes over.
enum MenuHighlightReader {
    /// Which stroke (by index) picked each word. A word goes to the first stroke that picks it.
    /// Only the middle of the pen counts, and it has to run across a good part of the word,
    /// so grazing the line above or the edge of a neighboring word picks nothing.
    static func assignments(words: [MenuWord], strokes: [HighlightStroke], fit: CGRect) -> [Int: Int] {
        var picked: [Int: Int] = [:]
        for (strokeIndex, stroke) in strokes.enumerated() {
            let samples = densePoints(stroke.points, step: 1)
            guard !samples.isEmpty else { continue }

            for word in words where picked[word.id] == nil {
                let rect = canvasRect(for: word, fit: fit)
                let inside = samples.filter { rect.contains($0) }.map(\.x)
                guard let minX = inside.min(), let maxX = inside.max() else { continue }
                if maxX - minX >= rect.width * 0.4 {
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
        let name = MenuCasing.fixed(stripPrice(joined(highlighted(.name))))
        let price = joined(highlighted(.price))

        let ingredients = ingredientItems(highlighted(.ingredients)).map(MenuCasing.fixed)

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
        let text = words.reduce(into: "") { text, word in
            if !text.isEmpty, word.spaceBefore { text += " " }
            text += word.text
        }
        return fixedAmpersands(text)
    }

    /// Script "&" on menus is often read as a lone "8" ("Butter 8 Bonded"). Between two
    /// words it can only be "&". Full-width "＆" is made plain too.
    static func fixedAmpersands(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"(?<=\p{L}[.,]?)\s+8\s+(?=\p{L})"#, with: " & ", options: .regularExpression)
            .replacingOccurrences(of: "＆", with: "&")
            .replacingOccurrences(of: "﹠", with: "&")
    }

    /// Ingredients come from the printed punctuation, not from where strokes start and stop.
    /// Menus differ, so the marks are weighed together for the whole highlighted text:
    /// - Commas, "&", "and", ";", "/", "·" split items.
    /// - A spaced dash is part of a name when the list already uses those marks
    ///   ("brown butter - washed rye, antica & demerara" → "brown butter-washed rye").
    ///   With no other marks it is the separator ("gin - lime - mint").
    /// - With no marks at all, one item per printed line.
    /// Words you skip over always split.
    static func ingredientItems(_ words: [MenuWord]) -> [String] {
        // Runs of words that sit next to each other on the menu.
        var runs: [[MenuWord]] = []
        for word in words {
            if let last = runs.last?.last, last.id + 1 == word.id {
                runs[runs.count - 1].append(word)
            } else {
                runs.append([word])
            }
        }

        let text = runs.map(joined).joined(separator: " ")
        if hasListMarks(text) {
            return runs.flatMap { splitIngredients(joinedDashes(joined($0))) }
        }
        if text.range(of: spacedDash, options: .regularExpression) != nil {
            return runs.flatMap { splitIngredients(joined($0).replacingOccurrences(of: spacedDash, with: ",", options: .regularExpression)) }
        }
        return runs
            .flatMap { run in Dictionary(grouping: run, by: \.line).sorted { $0.key < $1.key }.map(\.value) }
            .flatMap { splitIngredients(joined($0)) }
    }

    private static let listSeparators: Set<Character> = [",", "，", "、", "·", "•", "/", "|", ";", "；", "&", "＋", "+"]
    private static let spacedDash = #"\s+[-–—]\s+"#
    private static let andWord = #"(?i)\s+and\s+"#

    private static func hasListMarks(_ text: String) -> Bool {
        text.contains(where: listSeparators.contains)
            || text.range(of: andWord, options: .regularExpression) != nil
    }

    /// "brown butter - washed" → "brown butter-washed".
    private static func joinedDashes(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s+-\s+"#, with: "-", options: .regularExpression)
    }

    /// Splits a highlighted run like "Rye, Yellow Chartreuse & Orange Bitters" into items.
    static func splitIngredients(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: andWord, with: ",", options: .regularExpression)
            .split(whereSeparator: { listSeparators.contains($0) })
            .map { piece in
                // Commas inside quoted names leave stray quote marks behind; drop them.
                var item = stripPrice(String(piece))
                    .filter { !"“”\"".contains($0) }
                    .trimmingCharacters(in: CharacterSet(charactersIn: "*.-–—").union(.whitespaces))
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
}

/// Menus often print in ALL CAPS. Shouting words become Title Case ("ROUGH RIDER" → "Rough Rider");
/// abbreviations such as "XO", "VSOP" or "NYC" stay as printed. Mixed-case text is left alone.
enum MenuCasing {
    private static let abbreviations: Set<String> = [
        "XO", "VS", "VSOP", "XXO", "IPA", "ABV", "DOC", "DOCG", "AOC", "BBQ", "NYC", "LA", "UK", "USA", "US", "NV", "CBD", "OJ"
    ]
    private static let checker = UITextChecker()

    static func fixed(_ text: String) -> String {
        let pattern = #"[A-Za-z]+(?:['’][A-Za-z]+)*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = text
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let word = String(result[range])
            guard word.count >= 2, word == word.uppercased() else { continue }
            if isAbbreviation(word) { continue }
            result.replaceSubrange(range, with: word.prefix(1) + word.dropFirst().lowercased())
        }
        return result
    }

    /// Known drink abbreviations, anything without a vowel ("MKT"), and short letter
    /// groups that aren't English words ("NOLA" is kept, "OUR" is not).
    private static func isAbbreviation(_ word: String) -> Bool {
        if abbreviations.contains(word) { return true }
        if !word.contains(where: { "AEIOUY".contains($0) }) { return true }
        if word.count <= 4 {
            let lower = word.lowercased()
            let misspelled = checker.rangeOfMisspelledWord(
                in: lower, range: NSRange(location: 0, length: (lower as NSString).length),
                startingAt: 0, wrap: false, language: "en"
            )
            return misspelled.location != NSNotFound
        }
        return false
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
