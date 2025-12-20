//
//  LocationTestView.swift
//  ScytherExample
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import SwiftUI
import CoreLocation
import MapKit
import Scyther

struct LocationTestView: View {
    @StateObject private var locationManager = LocationTestManager()
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        List {
            Section {
                LabeledContent("Spoofing Enabled", value: Scyther.location.spoofingEnabled ? "Yes" : "No")
                    .foregroundStyle(Scyther.location.spoofingEnabled ? .green : .primary)
                LabeledContent("Swizzle Active", value: CLLocationManager.isLocationSwizzled ? "Yes" : "No")
                    .foregroundStyle(CLLocationManager.isLocationSwizzled ? .green : .red)

                if Scyther.location.spoofingEnabled {
                    LabeledContent("Spoofed Location", value: Scyther.location.spoofedLocation.name)
                    LabeledContent("Spoofed Lat", value: String(format: "%.6f", Scyther.location.spoofedLocation.latitude))
                    LabeledContent("Spoofed Lon", value: String(format: "%.6f", Scyther.location.spoofedLocation.longitude))
                }
            } header: {
                Text("Scyther Location Spoofer")
            } footer: {
                Text("Configure spoofing in Scyther Menu → Location Spoofer")
            }

            Section("CLLocationManager Reports") {
                switch locationManager.authorizationStatus {
                case .notDetermined:
                    Button("Request Location Permission") {
                        locationManager.requestPermission()
                    }
                case .denied, .restricted:
                    Text("Location access denied")
                        .foregroundStyle(.red)
                case .authorizedWhenInUse, .authorizedAlways:
                    if let location = locationManager.currentLocation {
                        LabeledContent("Latitude", value: String(format: "%.6f", location.coordinate.latitude))
                        LabeledContent("Longitude", value: String(format: "%.6f", location.coordinate.longitude))
                        LabeledContent("Accuracy", value: String(format: "%.1f m", location.horizontalAccuracy))
                        LabeledContent("Altitude", value: String(format: "%.1f m", location.altitude))
                        LabeledContent("Updated", value: location.timestamp.formatted(date: .omitted, time: .standard))

                        Button("Refresh Location") {
                            locationManager.requestLocation()
                        }
                    } else {
                        HStack {
                            Text("Fetching location...")
                            Spacer()
                            ProgressView()
                        }
                    }
                @unknown default:
                    Text("Unknown authorization status")
                }

                if let error = locationManager.error {
                    Text("Error: \(error)")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            if let location = locationManager.currentLocation {
                Section("Map") {
                    Map(position: $position) {
                        Marker("Current Location", coordinate: location.coordinate)
                    }
                    .frame(height: 250)
                    .listRowInsets(EdgeInsets())
                    .onAppear {
                        position = .camera(MapCamera(centerCoordinate: location.coordinate, distance: 10000))
                    }
                    .onChange(of: location.coordinate.latitude) { _, _ in
                        withAnimation {
                            position = .camera(MapCamera(centerCoordinate: location.coordinate, distance: 10000))
                        }
                    }
                }
            }

            Section {
                Button("Open Scyther Menu") {
                    Scyther.showMenu()
                }

                Button("Start Continuous Updates") {
                    locationManager.startUpdating()
                }

                Button("Stop Continuous Updates") {
                    locationManager.stopUpdating()
                }
                .foregroundStyle(.red)
            }
        }
        .navigationTitle("Location Test")
        .onAppear {
            if locationManager.authorizationStatus == .authorizedWhenInUse ||
               locationManager.authorizationStatus == .authorizedAlways {
                locationManager.requestLocation()
            }
        }
    }
}

class LocationTestManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var error: String?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = manager.authorizationStatus
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func requestLocation() {
        error = nil
        manager.requestLocation()
    }

    func startUpdating() {
        error = nil
        manager.startUpdatingLocation()
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        DispatchQueue.main.async {
            self.currentLocation = location
            self.error = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.error = error.localizedDescription
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorizationStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedWhenInUse ||
               manager.authorizationStatus == .authorizedAlways {
                self.requestLocation()
            }
        }
    }
}

#Preview {
    NavigationStack {
        LocationTestView()
    }
}
