import SwiftUI
import MapKit
import CoreLocation

struct LocationSelection {
    let coordinate: CLLocationCoordinate2D
    let name: String
    let city: String
}

struct LocationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var locationService: LocationService
    @StateObject private var searchCompleter = LocationSearchCompleter()

    let initialCoordinate: CLLocationCoordinate2D
    let confirmationTitle: String
    let onSelect: (LocationSelection) -> Void

    @State private var position: MapCameraPosition
    @State private var coordinate: CLLocationCoordinate2D
    @State private var pendingCoordinate: CLLocationCoordinate2D?
    @State private var showingLocationConfirmation = false
    @State private var visibleRegion: MKCoordinateRegion
    @State private var positioningAddress = ""
    @State private var city = ""
    @State private var isResolving = false
    @State private var resolveToken = UUID()
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var awaitingCurrentLocation = false
    @State private var suppressNextSuggestionUpdate = false
    @State private var searchedCoordinate: CLLocationCoordinate2D?
    @State private var searchedPointOfInterest = ""
    @State private var searchedSuggestedAddress = ""

    init(initialCoordinate: CLLocationCoordinate2D, confirmationTitle: String = "确认使用标记位置", onSelect: @escaping (LocationSelection) -> Void) {
        self.confirmationTitle = confirmationTitle
        self.initialCoordinate = initialCoordinate
        self.onSelect = onSelect
        _coordinate = State(initialValue: initialCoordinate)
        let region = MKCoordinateRegion(
            center: initialCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
        _visibleRegion = State(initialValue: region)
        _position = State(initialValue: .region(region))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            MapReader { mapProxy in
                Map(position: $position) {
                    Marker("拍摄地点", systemImage: "camera.fill", coordinate: coordinate)
                        .tint(LumenTheme.accent)
                    if let pendingCoordinate {
                        Marker("待确认地点", systemImage: "mappin", coordinate: pendingCoordinate)
                            .tint(.blue)
                    }
                }
                .mapControls {
                    MapCompass()
                    MapScaleView()
                }
                .onMapCameraChange(frequency: .onEnd) { context in
                    visibleRegion = context.region
                }
                .onTapGesture { point in
                    guard let selected = mapProxy.convert(point, from: .local) else { return }
                    pendingCoordinate = selected
                    showingLocationConfirmation = true
                }
            }

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索地点、道路或建筑", text: $searchText)
                        .submitLabel(.search)
                        .onSubmit(selectFirstSuggestion)
                        .onChange(of: searchText) { _, query in
                            if suppressNextSuggestionUpdate {
                                suppressNextSuggestionUpdate = false
                                return
                            }
                            searchCompleter.update(query: query, region: visibleRegion)
                        }
                    if isSearching {
                        ProgressView().controlSize(.small)
                    } else if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            searchCompleter.update(query: "", region: visibleRegion)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)

                if !searchCompleter.results.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(searchCompleter.results.prefix(6).enumerated()), id: \.offset) { index, result in
                            Button {
                                chooseSearchResult(result)
                            } label: {
                                HStack(spacing: 11) {
                                    Image(systemName: "mappin.and.ellipse")
                                        .foregroundStyle(LumenTheme.accent)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(result.title.isEmpty ? "所选地点" : result.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(LumenTheme.ink)
                                            .lineLimit(1)
                                        Text(result.subtitle.isEmpty ? "点击选择此位置" : result.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 14)
                                .frame(height: 58)
                            }
                            .buttonStyle(.plain)
                            if index < min(searchCompleter.results.count, 6) - 1 {
                                Divider().padding(.leading, 44)
                            }
                        }
                    }
                    .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Button {
                centerOnCurrentLocation()
            } label: {
                Label("当前定位", systemImage: "scope")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LumenTheme.ink)
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.14), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 16)
            .padding(.bottom, 188)

            VStack(alignment: .leading, spacing: 14) {
                Capsule()
                    .fill(.secondary.opacity(0.25))
                    .frame(width: 36, height: 5)
                    .frame(maxWidth: .infinity)

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "location.fill")
                        .foregroundStyle(LumenTheme.accent)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("拍摄地点 · 点击地图更换位置")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(isResolving ? "正在获取地址…" : (positioningAddress.isEmpty ? "点击地图选择拍摄位置" : positioningAddress))
                            .font(.subheadline)
                            .lineLimit(2)
                    }
                }

                Button {
                    onSelect(LocationSelection(
                        coordinate: coordinate,
                        name: positioningAddress,
                        city: city
                    ))
                    dismiss()
                } label: {
                    Text(confirmationTitle)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(LumenTheme.ink, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(isResolving)
                .opacity(isResolving ? 0.55 : 1)
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 18)
            .background(.ultraThickMaterial)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22))

        }
        .navigationTitle("选择拍摄地址")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
        }
        .alert("是否切换为这个拍摄地点？", isPresented: $showingLocationConfirmation, presenting: pendingCoordinate) { selected in
            Button("确认切换") {
                searchedCoordinate = nil
                searchedPointOfInterest = ""
                searchedSuggestedAddress = ""
                coordinate = selected
                pendingCoordinate = nil
                resolve(selected)
            }
            Button("保留原地点", role: .cancel) {
                pendingCoordinate = nil
            }
        } message: { _ in
            Text("蓝色标记是新选择的位置。确认后将移除原标记，并更新拍摄地址。")
        }
        .onChange(of: showingLocationConfirmation) { _, isPresented in
            if !isPresented { pendingCoordinate = nil }
        }
        .task { resolve(initialCoordinate) }
        .onChange(of: locationService.coordinate?.latitude) { _, _ in
            guard awaitingCurrentLocation, let current = locationService.coordinate else { return }
            awaitingCurrentLocation = false
            moveMap(to: current)
        }
    }

    private func resolve(_ coordinate: CLLocationCoordinate2D) {
        if let searchedCoordinate {
            let distance = CLLocation(
                latitude: searchedCoordinate.latitude,
                longitude: searchedCoordinate.longitude
            ).distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            if distance > 120 {
                self.searchedCoordinate = nil
                searchedPointOfInterest = ""
                searchedSuggestedAddress = ""
            }
        }
        positioningAddress = ""
        city = ""
        let token = UUID()
        resolveToken = token
        isResolving = true
        CLGeocoder().reverseGeocodeLocation(
            CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
            preferredLocale: Locale(identifier: "zh_CN")
        ) { placemarks, _ in
            DispatchQueue.main.async {
                guard resolveToken == token else { return }
                if let placemark = placemarks?.first {
                    city = (placemark.locality ?? placemark.administrativeArea ?? "")
                        .replacingOccurrences(of: "市", with: "")
                    let address = LocationService.address(
                        from: placemark,
                        pointOfInterest: searchedPointOfInterest,
                        suggestedAddress: searchedSuggestedAddress
                    )
                    positioningAddress = address.isEmpty
                        ? (placemark.name ?? placemark.subLocality ?? city)
                        : address
                }
                isResolving = false
            }
        }
    }

    private func selectFirstSuggestion() {
        guard let first = searchCompleter.results.first else { return }
        chooseSearchResult(first)
    }

    private func chooseSearchResult(_ result: MKLocalSearchCompletion) {
        isSearching = true
        let request = MKLocalSearch.Request(completion: result)
        Task {
            defer { isSearching = false }
            do {
                let response = try await MKLocalSearch(request: request).start()
                guard let item = response.mapItems.first else { return }
                searchedCoordinate = item.placemark.coordinate
                searchedPointOfInterest = item.name ?? result.title
                searchedSuggestedAddress = result.subtitle
                suppressNextSuggestionUpdate = true
                searchText = item.name ?? result.title
                searchCompleter.update(query: "", region: visibleRegion)
                moveMap(to: item.placemark.coordinate, span: 0.012)
            } catch {}
        }
    }

    private func centerOnCurrentLocation() {
        if let current = locationService.coordinate {
            moveMap(to: current)
        } else {
            awaitingCurrentLocation = true
            locationService.requestCurrentLocation()
        }
    }

    private func moveMap(to selectedCoordinate: CLLocationCoordinate2D, span: CLLocationDegrees = 0.02) {
        coordinate = selectedCoordinate
        withAnimation {
            position = .region(MKCoordinateRegion(
                center: selectedCoordinate,
                span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
            ))
        }
        resolve(selectedCoordinate)
    }
}

@MainActor
private final class LocationSearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published private(set) var results: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func update(query: String, region: MKCoordinateRegion) {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            completer.queryFragment = ""
            results = []
            return
        }
        completer.region = region
        completer.queryFragment = value
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let updatedResults = completer.results
        Task { @MainActor [weak self] in
            self?.results = updatedResults
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.results = []
        }
    }
}
