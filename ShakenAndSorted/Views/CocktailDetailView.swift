import SwiftUI
import SwiftData
import UIKit

struct CocktailDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var cocktail: Cocktail
    @State private var showingEdit = false
    @State private var showingDeleteConfirm = false
    @State private var viewingPhoto: UIImage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if cocktail.hasName {
                    Text(cocktail.trimmedName)
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(AppTheme.primaryText)
                }

                if let price = cocktail.trimmedPrice {
                    Text(price)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                }

                if !cocktail.cleanedIngredients.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Ingredients")
                            .font(.headline)
                            .foregroundStyle(AppTheme.primaryText)
                        ForEach(Array(cocktail.cleanedIngredients.enumerated()), id: \.offset) { _, ingredient in
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(AppTheme.accent)
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 7)
                                Text(ingredient)
                                    .foregroundStyle(AppTheme.primaryText)
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if cocktail.hasPlace {
                    placeRow
                }

                Text(cocktail.createdAt.formatted(date: .long, time: .omitted))
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)

                photoBlock
            }
            .padding(20)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit") { showingEdit = true }
                    Button("Delete", role: .destructive) { showingDeleteConfirm = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .fullScreenCover(item: $viewingPhoto) { image in
            PhotoViewer(image: image)
        }
        .sheet(isPresented: $showingEdit) {
            CocktailEditorView(mode: .edit(cocktail))
        }
        .confirmationDialog("Delete this drink?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                modelContext.delete(cocktail)
                dismiss()
            }
        }
    }

    @ViewBuilder
    private var photoBlock: some View {
        if let data = cocktail.photoData, let image = UIImage(data: data) {
            let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 260)
                .overlay {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        // Fill mode overflows the frame; clipping hides that part but it still catches taps.
                        .allowsHitTesting(false)
                }
                .clipShape(shape)
                .contentShape(shape)
                .onTapGesture { viewingPhoto = image }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("View photo")
        }
    }

    private var placeRow: some View {
        PlaceMapsMenu(cocktail: cocktail) {
            HStack(spacing: 8) {
                Image(systemName: "mappin.circle.fill")
                    .font(.title3)
                    .foregroundStyle(AppTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(cocktail.placeName ?? "")
                        .font(.body.weight(.medium))
                        .foregroundStyle(AppTheme.primaryText)
                    if let address = cocktail.placeAddress, !address.isEmpty {
                        Text(address)
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(AppTheme.tertiaryText)
            }
            .padding(14)
            .background(AppTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

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
    let cocktail: Cocktail
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
        [cocktail.placeName, cocktail.placeAddress]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private var coordinate: String? {
        cocktail.latitude.flatMap { lat in
            cocktail.longitude.map { lon in "\(lat),\(lon)" }
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
        components?.queryItems = [URLQueryItem(name: "q", value: cocktail.placeName ?? query)]
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

extension UIImage: @retroactive Identifiable {
    public var id: ObjectIdentifier { ObjectIdentifier(self) }
}

/// Full-screen photo: pinch to zoom, drag to look around, double-tap to zoom in or out.
private struct PhotoViewer: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZoomableImage(image: image)
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
