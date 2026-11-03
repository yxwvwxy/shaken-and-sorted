import SwiftUI
import MapKit
import CoreLocation

/// Picks the drink's place: suggestions while typing (from the first few letters,
/// nearest to you once location is allowed), bars nearby before typing, or your own text.
struct PlaceSearchView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var placeName: String?
    @Binding var placeAddress: String?
    @Binding var latitude: Double?
    @Binding var longitude: Double?

    @State private var query = ""
    @State private var completer = PlaceCompleter()
    @State private var location = LocationProvider()
    /// Bars and restaurants around you, nearest first: listed before typing, and matched
    /// against partial words while typing (Maps' own search needs whole words).
    @State private var nearby: [MKMapItem] = []
    @State private var localMatches: [MKMapItem] = []
    @State private var localSearch: Task<Void, Never>?
    /// Where Maps' top suggestions are, looked up so they can be ranked by distance too.
    @State private var resolved: [MKLocalSearchCompletion: MKMapItem] = [:]
    @State private var resolving: Task<Void, Never>?
    @State private var isResolving = false

    var body: some View {
        NavigationStack {
            List {
                if !trimmedQuery.isEmpty {
                    Button {
                        selectCustom(trimmedQuery)
                    } label: {
                        row(icon: "pencil", title: "Use “\(trimmedQuery)”", subtitle: "Custom place name")
                    }
                }

                if trimmedQuery.isEmpty {
                    nearbySection
                } else {
                    ForEach(candidates) { candidate in
                        Button {
                            switch candidate.source {
                            case .item(let item): selectMapItem(item)
                            case .completion(let completion): Task { await select(completion) }
                            }
                        } label: {
                            row(icon: "mappin.circle.fill", title: candidate.title, subtitle: candidate.subtitle)
                        }
                    }
                }

                if isResolving {
                    HStack {
                        ProgressView()
                        Text("Finding the place…")
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search or type a place")
            .onChange(of: query) { _, newValue in
                let text = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                completer.update(query: text)
                scheduleLocalSearch(for: text)
            }
            .onChange(of: completer.results) { _, results in
                resolveTopSuggestions(results)
            }
            .onChange(of: location.coordinate) { _, coordinate in
                guard let coordinate else { return }
                completer.focus(on: coordinate)
                Task { await loadNearby(around: coordinate) }
            }
            .onAppear { location.request() }
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

    @ViewBuilder
    private var nearbySection: some View {
        if location.isDenied {
            Text("Allow location in Settings to see bars near you first.")
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryText)
        } else if !nearby.isEmpty {
            Section("Nearby") {
                ForEach(Array(nearby.prefix(15).enumerated()), id: \.offset) { _, item in
                    Button {
                        selectMapItem(item)
                    } label: {
                        row(icon: "mappin.circle.fill", title: item.name ?? "Unknown place", subtitle: formattedAddress(for: item))
                    }
                }
            }
        }
    }

    private func row(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(AppTheme.primaryText)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// How well a name matches what's typed: 0 when it or one of its words starts with
    /// it ("lombar" → "Lombardi's", "Catherine Lombardi"), 1 when it's inside a word, 2 otherwise.
    private func matchScore(_ name: String) -> Int {
        let typed = trimmedQuery.lowercased()
        let title = name.lowercased()
        let words = title.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if title.hasPrefix(typed) || words.contains(where: { $0.hasPrefix(typed) }) { return 0 }
        if title.contains(typed) { return 1 }
        return 2
    }

    private struct Candidate: Identifiable {
        enum Source {
            case item(MKMapItem)
            case completion(MKLocalSearchCompletion)
        }
        var id: String
        var title: String
        var subtitle: String
        var score: Int
        var distance: CLLocationDistance?
        var order: Int
        var source: Source
    }

    /// Everything that matches what's typed, in one list: best text match first, then
    /// nearest; places whose location isn't known yet keep Maps' order after those that are.
    private var candidates: [Candidate] {
        var list: [Candidate] = []
        var seenNames: Set<String> = []

        let maxDistance: CLLocationDistance = 30_000
        for (offset, item) in Self.unique(nearby + localMatches).enumerated() {
            let name = item.name ?? ""
            let score = matchScore(name)
            let meters = distance(to: item)
            guard score < 2, meters.map({ $0 <= maxDistance }) ?? true else { continue }
            list.append(Candidate(
                id: "item-\(offset)-\(name)",
                title: name,
                subtitle: [meters.map(distanceText), formattedAddress(for: item)].compactMap { $0 }.joined(separator: " · "),
                score: score, distance: meters, order: offset, source: .item(item)
            ))
            seenNames.insert(name.lowercased())
        }

        for (offset, completion) in completer.results.enumerated() where !seenNames.contains(completion.title.lowercased()) {
            let item = resolved[completion]
            let meters = item.flatMap(distance(to:))
            list.append(Candidate(
                id: "completion-\(offset)-\(completion.title)-\(completion.subtitle)",
                title: completion.title,
                subtitle: [meters.map(distanceText), completion.subtitle].compactMap { $0 }.joined(separator: " · "),
                score: matchScore(completion.title), distance: meters, order: 1_000 + offset,
                source: item.map(Candidate.Source.item) ?? .completion(completion)
            ))
        }

        return list.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score < rhs.score }
            switch (lhs.distance, rhs.distance) {
            case let (left?, right?): return left < right
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return lhs.order < rhs.order
            }
        }
    }

    /// Looks up where Maps' first few suggestions are, so near ones can rise to the top.
    private func resolveTopSuggestions(_ results: [MKLocalSearchCompletion]) {
        resolving?.cancel()
        let top = results.prefix(8).filter { resolved[$0] == nil }
        guard !top.isEmpty, location.coordinate != nil else { return }
        resolving = Task {
            await withTaskGroup(of: (MKLocalSearchCompletion, MKMapItem?).self) { group in
                for completion in top {
                    group.addTask {
                        let item = try? await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start().mapItems.first
                        return (completion, item)
                    }
                }
                for await (completion, item) in group {
                    guard !Task.isCancelled else { return }
                    if let item { resolved[completion] = item }
                }
            }
        }
    }

    private func distance(to item: MKMapItem) -> CLLocationDistance? {
        guard let coordinate = location.coordinate, let place = item.placemark.location else { return nil }
        return CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude).distance(from: place)
    }

    private func distanceText(_ meters: CLLocationDistance) -> String {
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .naturalScale
        formatter.numberFormatter.maximumFractionDigits = 1
        return formatter.string(from: Measurement(value: meters, unit: UnitLength.meters))
    }

    /// Searches places around you for the typed text, shortly after typing stops.
    private func scheduleLocalSearch(for text: String) {
        localSearch?.cancel()
        guard !text.isEmpty else {
            localMatches = []
            return
        }
        localSearch = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = text
            request.resultTypes = .pointOfInterest
            request.pointOfInterestFilter = Self.drinkPlaces
            if let coordinate = location.coordinate {
                request.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 30_000, longitudinalMeters: 30_000)
            }
            let items = (try? await MKLocalSearch(request: request).start().mapItems) ?? []
            guard !Task.isCancelled else { return }
            localMatches = items
        }
    }

    private static let drinkPlaces = MKPointOfInterestFilter(
        including: [.nightlife, .restaurant, .cafe, .brewery, .winery, .hotel, .foodMarket]
    )

    /// One entry per place, however many searches found it.
    private static func unique(_ items: [MKMapItem]) -> [MKMapItem] {
        var seen: Set<String> = []
        return items.filter { item in
            let coordinate = item.placemark.coordinate
            let key = "\(item.name ?? "")|\((coordinate.latitude * 10_000).rounded())|\((coordinate.longitude * 10_000).rounded())"
            return seen.insert(key).inserted
        }
    }

    @MainActor
    private func loadNearby(around coordinate: CLLocationCoordinate2D) async {
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        var found: [MKMapItem] = []
        // Small circle first so the closest places are surely in; larger ones add more.
        for radius in [800.0, 2_500, 6_000] {
            let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: radius)
            request.pointOfInterestFilter = Self.drinkPlaces
            found += (try? await MKLocalSearch(request: request).start().mapItems) ?? []
        }
        nearby = Self.unique(found).sorted {
            here.distance(from: $0.placemark.location ?? here) < here.distance(from: $1.placemark.location ?? here)
        }
    }

    @MainActor
    private func select(_ completion: MKLocalSearchCompletion) async {
        isResolving = true
        defer { isResolving = false }
        let request = MKLocalSearch.Request(completion: completion)
        if let item = try? await MKLocalSearch(request: request).start().mapItems.first {
            selectMapItem(item, fallbackName: completion.title)
        } else {
            selectCustom(completion.title)
        }
    }

    private func selectCustom(_ name: String) {
        placeName = name
        placeAddress = nil
        latitude = nil
        longitude = nil
        dismiss()
    }

    private func selectMapItem(_ item: MKMapItem, fallbackName: String? = nil) {
        placeName = item.name ?? fallbackName ?? trimmedQuery
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

/// Live place suggestions from Apple Maps as you type, including partial words.
@Observable
private final class PlaceCompleter: NSObject, MKLocalSearchCompleterDelegate {
    var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .address]
    }

    func update(query: String) {
        if query.isEmpty {
            completer.cancel()
            results = []
        } else {
            completer.queryFragment = query
        }
    }

    /// Prefer places around you.
    func focus(on coordinate: CLLocationCoordinate2D) {
        completer.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 30_000, longitudinalMeters: 30_000)
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        results = []
    }
}

/// Asks for location while the place search is open; only used to rank and list nearby places.
@Observable
private final class LocationProvider: NSObject, CLLocationManagerDelegate {
    var coordinate: CLLocationCoordinate2D?
    var isDenied = false
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func request() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            isDenied = true
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            isDenied = false
            manager.requestLocation()
        case .denied, .restricted:
            isDenied = true
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        coordinate = locations.last?.coordinate
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

extension CLLocationCoordinate2D: @retroactive Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}
