import Foundation
import SwiftUI
import UIKit

struct MenuRecognitionResult: Codable, Equatable {
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

    init(name: String, ingredients: [String]) {
        self.name = name
        self.ingredients = ingredients
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        if let list = try? container.decode([String].self, forKey: .ingredients) {
            ingredients = list
        } else if let joined = try? container.decode(String.self, forKey: .ingredients) {
            ingredients = joined
                .split(whereSeparator: { $0 == "," || $0 == "\n" })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        } else {
            ingredients = []
        }
    }
}

enum MenuRecognitionError: LocalizedError {
    case noCircle
    case cropFailed
    case missingAPIKey
    case badResponse(String)
    case emptyRead

    var errorDescription: String? {
        switch self {
        case .noCircle:
            return "Circle the drink on the menu first."
        case .cropFailed:
            return "Could not crop that circle. Try a slightly larger loop."
        case .missingAPIKey:
            return "Add your OpenAI API key to recognize the menu."
        case .badResponse(let message):
            return message
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

enum MenuRecognizer {
    static let model = "gpt-4o-mini"

    private static let prompt = """
    This photo is a cropped piece of a cocktail menu. The user roughly circled one drink. Extra letters, prices, section titles, or a neighboring drink may show at the edges — ignore those.

    Return JSON only, with this shape:
    {"name":"","ingredients":[]}

    Rules:
    - name is the cocktail title. Use an empty string if unreadable.
    - ingredients is an array of ingredient names, one per item. Keep original language. Do not invent.
    - Do not include prices, ABV, or clearly decorative text.
    - If nothing can be read, return {"name":"","ingredients":[]}.
    """

    static func recognize(image: UIImage) async throws -> MenuRecognitionResult {
        let key = APIKeyStore.openAIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw MenuRecognitionError.missingAPIKey }
        guard let jpeg = image.jpegForAPI() else {
            throw MenuRecognitionError.cropFailed
        }

        let body: [String: Any] = [
            "model": model,
            "temperature": 0.1,
            "response_format": ["type": "json_object"],
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt],
                    [
                        "type": "image_url",
                        "image_url": [
                            "url": "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
                        ]
                    ]
                ]
            ]]
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            throw MenuRecognitionError.badResponse("Could not build the recognition request.")
        }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = httpBody

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status < 200 || status >= 300 {
            throw MenuRecognitionError.badResponse(Self.errorMessage(from: data, status: status))
        }

        let decoded = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        if let apiError = decoded.error?.message, !apiError.isEmpty {
            throw MenuRecognitionError.badResponse(apiError)
        }

        guard let content = decoded.choices.first?.message.content?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !content.isEmpty
        else {
            throw MenuRecognitionError.badResponse("The model returned an empty reply.")
        }

        let jsonData = extractJSONData(from: content)
        let result = try JSONDecoder().decode(MenuRecognitionResult.self, from: jsonData)
        guard result.hasAnything else { throw MenuRecognitionError.emptyRead }
        return result
    }

    private static func extractJSONData(from content: String) -> Data {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           (try? JSONDecoder().decode(MenuRecognitionResult.self, from: data)) != nil {
            return data
        }

        if let start = trimmed.firstIndex(of: "{"),
           let end = trimmed.lastIndex(of: "}"),
           start < end {
            return String(trimmed[start...end]).data(using: .utf8) ?? Data()
        }
        return trimmed.data(using: .utf8) ?? Data()
    }

    private static func errorMessage(from data: Data, status: Int) -> String {
        if let decoded = try? JSONDecoder().decode(OpenAIChatResponse.self, from: data),
           let message = decoded.error?.message, !message.isEmpty {
            return message
        }
        return "Recognition failed (\(status))."
    }
}

private struct OpenAIChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            var content: String?
        }
        var message: Message
    }

    struct ErrorBody: Decodable {
        var message: String?
    }

    var choices: [Choice]
    var error: ErrorBody?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        choices = try container.decodeIfPresent([Choice].self, forKey: .choices) ?? []
        error = try container.decodeIfPresent(ErrorBody.self, forKey: .error)
    }

    private enum CodingKeys: String, CodingKey {
        case choices, error
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

    func jpegForAPI(maxSide: CGFloat = 1280, quality: CGFloat = 0.7) -> Data? {
        let longest = max(size.width, size.height)
        let source: UIImage
        if longest > maxSide {
            let ratio = maxSide / longest
            let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
            source = UIGraphicsImageRenderer(size: newSize).image { _ in
                draw(in: CGRect(origin: .zero, size: newSize))
            }
        } else {
            source = self
        }
        return source.jpegData(compressionQuality: quality)
    }
}
