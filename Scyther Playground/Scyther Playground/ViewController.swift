//
//  ViewController.swift
//  Scyther Playground
//
//  Created by Brandon Stillitano on 12/2/21.
//

import MapKit
import Security
import Scyther
import UIKit

class ViewController: UIViewController, MKMapViewDelegate
{
    // MARK: - Data
    private let locationManager: CLLocationManager = CLLocationManager()

    // MARK: - UI Elements
    var tableView: UITableView = UITableView()
    var mapView: MKMapView = MKMapView()

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.

        //Setup Interface
        setupUI()
        setupConstraints()
        setupData()
    }

    func setupUI() {
        //Setup TableView
        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowHeight = UITableView.automaticDimension
        self.view.addSubview(tableView)

        //Setup MapView
        locationManager.delegate = self
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.requestAlwaysAuthorization()
        mapView.delegate = self
        mapView.showsUserLocation = true
        mapView.setUserTrackingMode(.follow, animated: true)
        self.view.addSubview(mapView)
    }

    func setupConstraints() {
        //Setup Table View Constraints
        tableView.snp.makeConstraints { (make) in
            make.edges.equalToSuperview()
        }

        //Setup MapView Constraints
        mapView.snp.makeConstraints { (make) in
            make.center.equalToSuperview()
            make.width.height.equalTo(350)
        }
    }
}

extension ViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer {
            tableView.deselectRow(at: indexPath, animated: true)
        }
        Scyther.presentMenu()
    }
}

extension ViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        //Init Cell
        let cellIdentifier: String = String("cellIdentifier")
        var cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier)

        //Adjust Cell
        cell = UITableViewCell(style: .default, reuseIdentifier: cellIdentifier)
        cell?.accessoryType = .none
        cell?.selectionStyle = .none

        cell?.textLabel?.text = "Open Scyther"

        return cell ?? UITableViewCell()
    }
}

extension ViewController {
    func setupData() {
        setupCookies()
        setupKeychain()
        setupFlags()
        setupEnvironments()
        setupDeveloperTools()
    }

    func setupCookies() {
        if let cookie = HTTPCookie(properties: [
                .domain: ".test.scyther.com",
                .path: "/",
                .name: "ScytherCookie",
                .value: "K324klj23KLJKH223423CookieValueDSFLJ234",
                .secure: "FALSE",
                .discard: "TRUE"
            ]) {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
        if let cookie = HTTPCookie(properties: [
                .domain: ".test.scyther.com",
                .path: "/",
                .name: "ScytherCookie2",
                .value: "K324klj23KLJKH223423CookieValueDSFLJ234",
                .secure: "FALSE",
                .discard: "TRUE"
            ]) {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
        if let cookie = HTTPCookie(properties: [
                .domain: ".test.scyther.com",
                .path: "/",
                .name: "ScytherCookie3",
                .value: "K324klj23KLJKH223423CookieValueDSFLJ234",
                .secure: "FALSE",
                .discard: "TRUE"
            ]) {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
        if let cookie = HTTPCookie(properties: [
                .domain: ".test.scyther.com",
                .path: "/",
                .name: "ScytherCookie4",
                .value: "K324klj23KLJKH223423CookieValueDSFLJ234",
                .secure: "FALSE",
                .discard: "TRUE"
            ]) {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }

    func setupKeychain() {
        //Clear Existing Keychain Items
        let secItemClasses = [
            kSecClassGenericPassword,
            kSecClassInternetPassword,
            kSecClassCertificate,
            kSecClassKey,
            kSecClassIdentity
        ]
        for secItemClass in secItemClasses {
            let dictionary = [kSecClass as String: secItemClass]
            SecItemDelete(dictionary as CFDictionary)
        }

        //Setup Generic Keychain
        for i in 0...12 {
            let username = "john"
            let password = "69420".data(using: .utf8)!
            let attributes: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: "\(username)+\(i)",
                kSecValueData as String: password
            ]
            if SecItemAdd(attributes as CFDictionary, nil) == noErr {
                print("User saved successfully in the keychain")
            } else {
                print("Something went wrong trying to save the user in the keychain")
            }
        }

        //Setup Internet Keychain
        for i in 0...12 {
            let username = "internet-boi"
            let password = "1337-h4x0r".data(using: .utf8)!
            let attributes: [String: Any] = [
                kSecClass as String: kSecClassInternetPassword,
                kSecAttrAccount as String: "\(username)+\(i)",
                kSecValueData as String: password
            ]
            if SecItemAdd(attributes as CFDictionary, nil) == noErr {
                print("User saved successfully in the keychain")
            } else {
                print("Something went wrong trying to save the user in the keychain")
            }
        }
    }

    func setupFlags() {
        var flags: [String: Bool] = [:]
        flags["logging"] = true
        flags["analytics"] = false
        flags["voip-calling"] = true
        flags["live-chat"] = true
        flags["force-update"] = false
        flags["advertising"] = true
        flags["offline-cache"] = true
        flags["push-notifications"] = true
        flags["backend-sync"] = false
        flags["rtl-layout"] = true
        flags["google-news-bypass"] = false
        flags["development-environment"] = false
        for key: String in flags.keys {
            Scyther.toggler.configureToggle(withName: key,
                                            remoteValue: flags[key] ?? false)
        }
    }

    func setupEnvironments() {
        for environment in Environments.allCases {
            Scyther.configSwitcher.configureEnvironment(withIdentifier: environment.rawValue,
                                                        variables: environment.environmentVariables)
        }
    }

    func setupDeveloperTools() {
        //Setup Red View Controller
        var redOption: DeveloperOption = DeveloperOption()
        redOption.name = "Red View Controller"
        redOption.icon = UIImage(systemImage: "megaphone")
        redOption.viewController = RedViewController()
        Scyther.instance.developerOptions.append(redOption)

        //Setup Blue View Controller
        var blueOption: DeveloperOption = DeveloperOption()
        blueOption.name = "Blue View Controller"
        blueOption.icon = UIImage(systemImage: "location.circle")
        blueOption.viewController = BlueViewController()
        Scyther.instance.developerOptions.append(blueOption)
    }
}

extension ViewController: CLLocationManagerDelegate {
    func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
        let region = MKCoordinateRegion.init(center: userLocation.coordinate, span: MKCoordinateSpan.init(latitudeDelta: 0.01, longitudeDelta: 0.01))
        mapView.setRegion(region, animated: true)
    }
}
