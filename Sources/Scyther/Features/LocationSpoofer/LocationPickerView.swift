//
//  LocationPickerView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 30/1/2025.
//

import Combine
import MapKit
import SwiftUI

/// A SwiftUI view for selecting custom location coordinates.
///
/// `LocationPickerView` provides an interactive map interface for choosing a custom
/// location by either dragging the map or entering latitude/longitude coordinates
/// directly. Changes are debounced to provide smooth interaction.
///
/// ## Features
/// - Interactive map with centered pin
/// - Text fields for manual coordinate entry
/// - Debounced coordinate updates (500ms)
/// - Real-time synchronization between map and text fields
/// - Save functionality to persist the selected location
///
/// ## Usage
/// ```swift
/// NavigationStack {
///     LocationPickerView()
/// }
/// ```
///
/// - Note: The view loads the currently selected custom location when it appears.
struct LocationPickerView: View {
    @State private var region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: Location.sydney.latitude, longitude: Location.sydney.longitude), span: MKCoordinateSpan(latitudeDelta: 0.7, longitudeDelta: 0.7))
    @State private var longitude: String = ""
    @State private var latitude: String = ""
    private var latitudePublisher = PassthroughSubject<String, Never>()
    private var longitudePublisher = PassthroughSubject<String, Never>()
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        List {
            SwiftUI.Section {
                ZStack {
                    Map(coordinateRegion: $region)
                        .frame(height: 300)
                    Image(uiImage: UIImage(systemImage: "mappin")?.withRenderingMode(.alwaysTemplate) ?? UIImage())
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 40, height: 40)
                        .foregroundStyle(Color.red)
                }.listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            } header: {
                Text("Map")
            } footer: {
                Text("Drag the map to the location you would like to spoof your app to. This will only affect this app, all other location services will remain accurate.")
            }
            SwiftUI.Section {
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
            } header: {
                Text("Coordinates")
            } footer: {
                Text("Use these text fields to type the coordinates of the location you'd like to spoof.")
            }
        }.onAppear {
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
        }.toolbar {
            ToolbarItemGroup(placement: .confirmationAction) {
                Button("Save") {
                    LocationSpoofer.instance.setCustomLocation(region.center)
                    presentationMode.wrappedValue.dismiss()
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
        .navigationTitle("Custom Location")
            .navigationBarTitleDisplayMode(.inline)
    }
    
    func setupRegion() {
        let location = LocationSpoofer.instance.customLocation
        region.center.latitude = location.latitude
        region.center.longitude = location.longitude
        latitude = location.latitude.description
        longitude = location.longitude.description
    }

    func setLatitude(_ string: String) {
        guard let double = Double(string) else { return }
        region.center.latitude = double
    }

    func setLongitude(_ string: String) {
        guard let double = Double(string) else { return }
        region.center.longitude = double
    }
}

class LocationPickerViewController: UIHostingController<LocationPickerView> { }

#Preview {
    NavigationView {
        LocationPickerView()
    }
}
