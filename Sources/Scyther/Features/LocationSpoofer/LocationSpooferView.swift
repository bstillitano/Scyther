//
//  LocationSpooferView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 17/4/2025.
//

import Combine
import MapKit
import SwiftUI

/// A SwiftUI view for configuring and managing location spoofing.
///
/// `LocationSpooferView` provides a comprehensive interface for selecting spoofed locations,
/// including preset cities, routes, and custom coordinates. It includes an interactive map
/// and segmented control for switching between location types.
///
/// ## Features
/// - Toggle to enable/disable location spoofing
/// - Interactive map showing the selected location
/// - Segmented control for cities, routes, and custom locations
/// - List of preset cities and routes
/// - Text fields for entering custom coordinates
/// - Real-time map updates as locations are selected
///
/// ## Usage
/// ```swift
/// NavigationStack {
///     LocationSpooferView()
/// }
/// ```
struct LocationSpooferView: View {
    @State private var isEnabled: Bool = false
    @State private var region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: Location.sydney.latitude, longitude: Location.sydney.longitude), span: MKCoordinateSpan(latitudeDelta: 0.7, longitudeDelta: 0.7))
    @State private var longitude: String = ""
    @State private var latitude: String = ""
    private var latitudePublisher = PassthroughSubject<String, Never>()
    private var longitudePublisher = PassthroughSubject<String, Never>()
    @Environment(\.presentationMode) var presentationMode
    @State private var presetType: LocationSpooferPresetType = .city
    @State private var selectedLocation: Location?
    @State private var selectedRoute: Route?
    
    var body: some View {
        List {
            Section {
                Toggle(isOn: $isEnabled) {
                    Text("Enable location spoofing")
                }
            } footer: {
                Text("This will only affect this app. All other apps and device location services will remain accurate.")
            }
            
            if isEnabled {
                Section {
                    mapView
                }
                
                Section {
                    content
                } header: {
                    presetTypePicker
                }
            }
        }
        .animation(.default, value: isEnabled)
        .onAppear {
            setupRegion()
        }.onChange(of: latitude) { newValue in
            latitudePublisher.send(newValue)
        }.onChange(of: longitude) { newValue in
            longitudePublisher.send(newValue)
        }.onChange(of: region) { newValue in
            latitude = newValue.center.latitude.description
            longitude = newValue.center.longitude.description
        }.onReceive(latitudePublisher.debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)) { newValue in
            setLatitude(newValue)
        }.onReceive(longitudePublisher.debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)) { newValue in
            setLongitude(newValue)
        }
        .onChange(of: isEnabled) { newValue in
            LocationSpoofer.instance.spoofingEnabled = newValue
        }
        .navigationTitle("Location Spoofer")
    }
    
    private var presetTypePicker: some View {
        Picker("Preset Type", selection: $presetType) {
            ForEach(LocationSpooferPresetType.allCases, id: \.rawValue) { value in
                Text(value.label)
                    .tag(value)
            }
        }
        .pickerStyle(.segmented)
        .listRowInsets(EdgeInsets(.zero))
        .padding(.bottom)
        .textCase(nil)
    }
    
    private var mapView: some View {
        ZStack {
            Map(coordinateRegion: $region, showsUserLocation: true)
                .frame(height: 300)
            Image(uiImage: UIImage(systemImage: "mappin")?.withRenderingMode(.alwaysTemplate) ?? UIImage())
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
                .foregroundStyle(Color.red)
        }.listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
    }
    
    @ViewBuilder private var content: some View {
        switch presetType {
        case .city:
            citiesContent
        case .route:
            routesContent
        case .custom:
            customLocationContent
        }
    }
    
    private var citiesContent: some View {
        ForEach(LocationSpooferPresets.allCases.filter { $0.type == .city }, id: \.self) { value in
            LabeledContent {
                if selectedLocation == value.location {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            } label: {
                Text(value.location!.name)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                guard let location = value.location else { return }
                selectLocation(location)
            }
        }
    }

    private var routesContent: some View {
        ForEach(LocationSpooferPresets.allCases.filter { $0.type == .route }, id: \.self) { value in
            LabeledContent {
                if selectedRoute == value.route {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            } label: {
                Text(value.route!.name)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                guard let route = value.route else { return }
                selectRoute(route)
            }
        }
    }
    
    @ViewBuilder private var customLocationContent: some View {
        HStack {
            Text("Latitude")
            Spacer()
            TextField("Latitude", text: $latitude)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
        }
        HStack {
            Text("Longitude")
            Spacer()
            TextField("Longitude", text: $longitude)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
        }
    }
    
    func setupRegion() {
        isEnabled = LocationSpoofer.instance.spoofingEnabled

        // Load current selection
        if LocationSpoofer.instance.useCustomLocation {
            presetType = .custom
            selectedLocation = nil
            selectedRoute = nil
            let location = LocationSpoofer.instance.customLocation
            region.center.latitude = location.latitude
            region.center.longitude = location.longitude
            latitude = location.latitude.description
            longitude = location.longitude.description
        } else if let route = LocationSpoofer.instance.spoofedRoute {
            presetType = .route
            selectedRoute = route
            selectedLocation = nil
        } else {
            presetType = .city
            let location = LocationSpoofer.instance.spoofedLocation
            selectedLocation = location
            selectedRoute = nil
            region.center.latitude = location.latitude
            region.center.longitude = location.longitude
            latitude = location.latitude.description
            longitude = location.longitude.description
        }
    }

    func selectLocation(_ location: Location) {
        selectedLocation = location
        selectedRoute = nil
        LocationSpoofer.instance.spoofedLocation = location

        // Update map
        withAnimation {
            region.center.latitude = location.latitude
            region.center.longitude = location.longitude
        }
        latitude = location.latitude.description
        longitude = location.longitude.description
    }

    func selectRoute(_ route: Route) {
        selectedRoute = route
        selectedLocation = nil
        LocationSpoofer.instance.spoofedRoute = route
    }

    func setLatitude(_ string: String) {
        guard let double = Double(string) else { return }
        region.center.latitude = double
        if presetType == .custom {
            saveCustomLocation()
        }
    }

    func setLongitude(_ string: String) {
        guard let double = Double(string) else { return }
        region.center.longitude = double
        if presetType == .custom {
            saveCustomLocation()
        }
    }

    func saveCustomLocation() {
        selectedLocation = nil
        selectedRoute = nil
        LocationSpoofer.instance.useCustomLocation = true
        LocationSpoofer.instance.setCustomLocation(region.center)
    }
}

#Preview {
    LocationSpooferView()
}
