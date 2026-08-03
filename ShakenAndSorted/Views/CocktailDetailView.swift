import SwiftUI
import SwiftData
import MapKit
import UIKit

struct CocktailDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var cocktail: Cocktail
    @State private var showingEdit = false
    @State private var showingDeleteConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                photoHeader

                VStack(alignment: .leading, spacing: 8) {
                    Text(cocktail.displayTitle)
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(AppTheme.primaryText)

                    Text(cocktail.createdAt.formatted(date: .long, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                }

                if cocktail.hasPlace {
                    placeRow
                }

                if !cocktail.ingredients.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Ingredients")
                            .font(.headline)
                            .foregroundStyle(AppTheme.primaryText)
                        ForEach(Array(cocktail.ingredients.enumerated()), id: \.offset) { _, ingredient in
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
    private var photoHeader: some View {
        if let data = cocktail.photoData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var placeRow: some View {
        Button(action: openInMaps) {
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
        .buttonStyle(.plain)
    }

    private func openInMaps() {
        if let lat = cocktail.latitude, let lon = cocktail.longitude {
            let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            let placemark = MKPlacemark(coordinate: coordinate)
            let item = MKMapItem(placemark: placemark)
            item.name = cocktail.placeName
            item.openInMaps()
            return
        }

        var components = URLComponents(string: "http://maps.apple.com/")
        let query = [cocktail.placeName, cocktail.placeAddress]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        if let url = components?.url {
            UIApplication.shared.open(url)
        }
    }
}
