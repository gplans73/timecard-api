import Foundation
import CoreLocation
import MapKit
import Contacts

final class RegionLocator: NSObject, CLLocationManagerDelegate {
    static let shared = RegionLocator()

    private let locationManager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func detectRegion() async throws -> (countryCode: String?, adminCode: String?) {
        guard CLLocationManager.locationServicesEnabled() else {
            throw CLError(.locationUnknown)
        }

        try await requestAuthorizationIfNeeded()

        let location = try await requestLocation()

        let (countryCode, adminCode) = try await reverseGeocode(location: location)
        return (countryCode, adminCode)
    }

    private func requestAuthorizationIfNeeded() async throws {
        let status: CLAuthorizationStatus
        if #available(iOS 14.0, *) {
            status = locationManager.authorizationStatus
        } else {
            status = CLLocationManager.authorizationStatus()
        }
        switch status {
        case .notDetermined:
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                self.authorizationContinuation = continuation
                self.locationManager.requestWhenInUseAuthorization()
            }
        case .restricted, .denied:
            throw CLError(.denied)
        case .authorizedAlways, .authorizedWhenInUse:
            return
        @unknown default:
            throw CLError(.denied)
        }
    }

    private var authorizationContinuation: CheckedContinuation<Void, Error>?

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard let continuation = authorizationContinuation else { return }
        let status: CLAuthorizationStatus
        if #available(iOS 14.0, *) {
            status = manager.authorizationStatus
        } else {
            status = CLLocationManager.authorizationStatus()
        }
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            continuation.resume()
            authorizationContinuation = nil
        case .denied, .restricted:
            continuation.resume(throwing: CLError(.denied))
            authorizationContinuation = nil
        case .notDetermined:
            break
        @unknown default:
            continuation.resume(throwing: CLError(.denied))
            authorizationContinuation = nil
        }
    }

    private func requestLocation() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CLLocation, Error>) in
            self.locationContinuation = continuation
            self.locationManager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let continuation = locationContinuation else { return }
        if let location = locations.last {
            continuation.resume(returning: location)
        } else {
            continuation.resume(throwing: CLError(.locationUnknown))
        }
        locationContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard let continuation = locationContinuation else { return }
        continuation.resume(throwing: error)
        locationContinuation = nil
    }

    private func reverseGeocode(location: CLLocation) async throws -> (countryCode: String?, adminCode: String?) {
        if #available(iOS 26.0, *) {
            // Use MapKit's MKReverseGeocodingRequest for iOS 26+
            guard let request = MKReverseGeocodingRequest(location: location) else {
                throw CLError(.geocodeFoundNoResult)
            }
            let items = try await request.mapItems
            if let item = items.first {
                // Use MKMapItem.placemark to extract region codes (iOS 26+)
                let placemark = item.placemark
                let countryCode = placemark.countryCode
                var adminCode: String? = placemark.administrativeArea
                if adminCode?.isEmpty ?? true {
                    adminCode = placemark.subAdministrativeArea
                }
                return (countryCode, adminCode)
            } else {
                throw CLError(.geocodeFoundNoResult)
            }
        } else if #available(iOS 15.0, *) {
            // Use Core Location's CLGeocoder for iOS 15–25
            let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
            if let placemark = placemarks.first {
                let countryCode = placemark.isoCountryCode
                var adminCode: String? = placemark.administrativeArea
                if adminCode?.isEmpty ?? true {
                    adminCode = placemark.subAdministrativeArea
                }
                return (countryCode, adminCode)
            } else {
                throw CLError(.geocodeFoundNoResult)
            }
        } else {
            // Legacy fallback for < iOS 15
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(String?, String?), Error>) in
                CLGeocoder().reverseGeocodeLocation(location) { placemarks, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    if let placemark = placemarks?.first {
                        let countryCode = placemark.isoCountryCode
                        var adminCode: String? = placemark.administrativeArea
                        if adminCode?.isEmpty ?? true {
                            adminCode = placemark.subAdministrativeArea
                        }
                        continuation.resume(returning: (countryCode, adminCode))
                    } else {
                        continuation.resume(throwing: CLError(.geocodeFoundNoResult))
                    }
                }
            }
        }
    }
}
