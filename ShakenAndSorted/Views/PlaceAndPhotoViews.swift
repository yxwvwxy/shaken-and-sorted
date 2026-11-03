import SwiftUI
import SwiftData
import UIKit

/// Which map app a tapped place opens in, chosen in Settings.
enum MapApp: String, CaseIterable, Identifiable {
    case ask
    case apple
    case google

    static let storageKey = "defaultMapApp"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ask: return "Ask Every Time"
        case .apple: return "Apple Maps"
        case .google: return "Google Maps"
        }
    }
}

/// Tapping the label opens the place in the default map app from Settings, or
/// lists the map apps when there is none. A long press always lists them.
struct PlaceMapsMenu<Label: View>: View {
    let placeName: String?
    let placeAddress: String?
    let latitude: Double?
    let longitude: Double?
    @ViewBuilder let label: () -> Label
    @AppStorage(MapApp.storageKey) private var defaultApp: MapApp = .ask
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            switch defaultApp {
            case .ask:
                Menu { choices } label: { label() }
            case .apple:
                Menu { choices } label: { label() } primaryAction: { openInAppleMaps() }
            case .google:
                Menu { choices } label: { label() } primaryAction: { openInGoogleMaps() }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var choices: some View {
        Button("Apple Maps", systemImage: "map", action: openInAppleMaps)
        Button("Google Maps", systemImage: "globe", action: openInGoogleMaps)
        Button("Copy Address", systemImage: "doc.on.doc") {
            UIPasteboard.general.string = query
        }
    }

    private var query: String {
        [placeName, placeAddress]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private var coordinate: String? {
        latitude.flatMap { lat in
            longitude.map { lon in "\(lat),\(lon)" }
        }
    }

    private func open(_ url: URL, orElse fallback: URL? = nil) {
        openURL(url) { opened in
            if !opened, let fallback {
                openURL(fallback)
            }
        }
    }

    private func openInAppleMaps() {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [URLQueryItem(name: "q", value: placeName ?? query)]
            + (coordinate.map { [URLQueryItem(name: "ll", value: $0)] }
                ?? [URLQueryItem(name: "address", value: query)])
        if let url = components?.url {
            open(url)
        }
    }

    /// Google Maps app if installed, otherwise the Google Maps website.
    private func openInGoogleMaps() {
        let search = query.isEmpty ? (coordinate ?? "") : query

        var web = URLComponents(string: "https://www.google.com/maps/search/")
        web?.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "query", value: search)
        ]
        guard let webURL = web?.url else { return }

        var app = URLComponents(string: "comgooglemaps://")
        app?.queryItems = [URLQueryItem(name: "q", value: search)]
            + (coordinate.map { [URLQueryItem(name: "center", value: $0)] } ?? [])
        guard let appURL = app?.url, UIApplication.shared.canOpenURL(appURL) else {
            open(webURL)
            return
        }
        open(appURL, orElse: webURL)
    }
}

/// Full-screen photos: swipe between them; pinch to zoom, drag to look around,
/// double-tap to zoom in or out.
struct PhotoViewer: View {
    let images: [UIImage]
    @State private var index: Int
    @Environment(\.dismiss) private var dismiss

    init(images: [UIImage], startIndex: Int = 0) {
        self.images = images
        _index = State(initialValue: min(max(startIndex, 0), max(images.count - 1, 0)))
    }

    var body: some View {
        TabView(selection: $index) {
            ForEach(Array(images.enumerated()), id: \.offset) { offset, image in
                ZoomableImage(image: image)
                    .tag(offset)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .always : .never))
        .ignoresSafeArea()
        .background(Color.black.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.black.opacity(0.5), in: Circle())
            }
            .padding()
            .accessibilityLabel("Close")
        }
    }
}

private struct ZoomableImage: UIViewRepresentable {
    let image: UIImage

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 6
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.backgroundColor = .black
        scrollView.delegate = context.coordinator

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        if scrollView.zoomScale == 1 {
            context.coordinator.imageView?.frame = scrollView.bounds
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        @objc func doubleTapped(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
                return
            }
            let point = gesture.location(in: imageView)
            let size = CGSize(width: scrollView.bounds.width / 3, height: scrollView.bounds.height / 3)
            scrollView.zoom(
                to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height),
                animated: true
            )
        }
    }
}
