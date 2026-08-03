import SwiftUI
import MapKit

struct PlaceSearchView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var placeName: String?
    @Binding var placeAddress: String?
    @Binding var latitude: Double?
    @Binding var longitude: Double?

    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            List {
                if !trimmedQuery.isEmpty {
                    Button {
                        selectCustom(trimmedQuery)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "pencil")
                                .foregroundStyle(AppTheme.accent)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Use “\(trimmedQuery)”")
                                    .foregroundStyle(AppTheme.primaryText)
                                Text("Custom place name")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.secondaryText)
                            }
                        }
                    }
                }

                if isSearching {
                    HStack {
                        ProgressView()
                        Text("Searching maps…")
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }

                ForEach(Array(results.enumerated()), id: \.offset) { _, item in
                    Button {
                        selectMapItem(item)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(AppTheme.accent)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name ?? "Unknown place")
                                    .foregroundStyle(AppTheme.primaryText)
                                Text(formattedAddress(for: item))
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.secondaryText)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, prompt: "Search or type a place")
            .onChange(of: query) { _, newValue in
                scheduleSearch(for: newValue)
            }
            .navigationTitle("Where")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .tint(AppTheme.accent)
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func scheduleSearch(for text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            isSearching = false
            return
        }

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await searchMaps(for: trimmed)
        }
    }

    @MainActor
    private func searchMaps(for text: String) async {
        isSearching = true
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = [.pointOfInterest, .address]

        do {
            let response = try await MKLocalSearch(request: request).start()
            guard !Task.isCancelled else { return }
            results = response.mapItems
        } catch {
            if !Task.isCancelled {
                results = []
            }
        }
        isSearching = false
    }

    private func selectCustom(_ name: String) {
        placeName = name
        placeAddress = nil
        latitude = nil
        longitude = nil
        dismiss()
    }

    private func selectMapItem(_ item: MKMapItem) {
        placeName = item.name ?? trimmedQuery
        placeAddress = formattedAddress(for: item)
        latitude = item.placemark.coordinate.latitude
        longitude = item.placemark.coordinate.longitude
        dismiss()
    }

    private func formattedAddress(for item: MKMapItem) -> String {
        let placemark = item.placemark
        let parts = [
            placemark.thoroughfare,
            placemark.locality,
            placemark.administrativeArea,
            placemark.postalCode
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }

        if parts.isEmpty {
            return item.placemark.title ?? ""
        }
        return parts.joined(separator: ", ")
    }
}
