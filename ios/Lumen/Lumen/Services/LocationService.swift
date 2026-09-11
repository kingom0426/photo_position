import CoreLocation
import Foundation

@MainActor
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var city: String?
    @Published private(set) var placeName: String?
    @Published private(set) var detailedAddress: String?
    @Published private(set) var isLocating = false
    @Published private(set) var errorMessage: String?

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestCurrentLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            isLocating = true
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            isLocating = true
            manager.requestLocation()
        case .restricted, .denied:
            isLocating = false
            errorMessage = "定位权限未开启，可在系统设置中允许访问位置"
        @unknown default:
            isLocating = false
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
                isLocating = true
                manager.requestLocation()
            } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
                isLocating = false
                errorMessage = "定位权限未开启，可在系统设置中允许访问位置"
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            coordinate = location.coordinate
            isLocating = false
            geocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "zh_CN")) { [weak self] placemarks, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let placemark = placemarks?.first {
                        self.city = Self.normalizedCity(placemark.locality ?? placemark.administrativeArea)
                        self.placeName = placemark.name ?? placemark.subLocality ?? self.city
                        self.detailedAddress = Self.address(from: placemark)
                        self.errorMessage = nil
                    } else if let error {
                        self.errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            isLocating = false
            errorMessage = error.localizedDescription
        }
    }

    private static func normalizedCity(_ value: String?) -> String? {
        value?.replacingOccurrences(of: "市", with: "")
    }

    static func address(
        from placemark: CLPlacemark,
        pointOfInterest: String? = nil,
        suggestedAddress: String? = nil
    ) -> String {
        var components = [
            placemark.administrativeArea,
            placemark.locality,
            placemark.subLocality,
            placemark.thoroughfare,
            placemark.subThoroughfare,
            placemark.name
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        components = components.reduce(into: []) { result, value in
            guard !value.isEmpty, !result.contains(value) else { return }
            result.append(value)
        }
        let geocodedAddress = components.joined()
        let suggestion = suggestedAddress?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var address = suggestion.count > geocodedAddress.count ? suggestion : geocodedAddress
        let poi = pointOfInterest?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !poi.isEmpty, !address.contains(poi) {
            address += address.isEmpty ? poi : " \(poi)"
        }
        return address
    }
}
