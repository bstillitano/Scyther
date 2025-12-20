//
//  RouteTests.swift
//  ScytherTests
//
//  Created by Brandon Stillitano on 21/12/2025.
//

@testable import Scyther
import XCTest

final class RouteTests: XCTestCase {

    // MARK: - Initialization Tests

    func testInitialization() {
        let route = Route(
            id: "test-route",
            name: "Test Route",
            fileName: "TestRoute",
            updateInterval: 5.0
        )

        XCTAssertEqual(route.id, "test-route")
        XCTAssertEqual(route.name, "Test Route")
        XCTAssertEqual(route.fileName, "TestRoute")
        XCTAssertEqual(route.updateInterval, 5.0)
    }

    func testInitializationWithDifferentUpdateInterval() {
        let route = Route(
            id: "fast-route",
            name: "Fast Route",
            fileName: "FastRoute",
            updateInterval: 1.0
        )

        XCTAssertEqual(route.updateInterval, 1.0)
    }

    // MARK: - Preset Tests

    func testDriveCityToSuburbPreset() {
        let preset = Route.driveCityToSuburb

        XCTAssertEqual(preset.id, "cityToSuburb")
        XCTAssertEqual(preset.name, "Drive from city to suburb")
        XCTAssertEqual(preset.fileName, "DriveCityToSuburb")
        XCTAssertEqual(preset.updateInterval, 5.0)
    }

    // MARK: - Equatable Tests

    func testEqualityBySameId() {
        let route1 = Route(
            id: "test-route",
            name: "Route One",
            fileName: "RouteOne",
            updateInterval: 1.0
        )

        let route2 = Route(
            id: "test-route",
            name: "Route Two",
            fileName: "RouteTwo",
            updateInterval: 10.0
        )

        XCTAssertEqual(route1, route2)
    }

    func testInequalityByDifferentId() {
        let route1 = Route(
            id: "route-1",
            name: "Same Name",
            fileName: "SameFile",
            updateInterval: 5.0
        )

        let route2 = Route(
            id: "route-2",
            name: "Same Name",
            fileName: "SameFile",
            updateInterval: 5.0
        )

        XCTAssertNotEqual(route1, route2)
    }

    // MARK: - Property Mutation Tests

    func testIdMutation() {
        var route = Route(
            id: "original",
            name: "Test",
            fileName: "Test",
            updateInterval: 5.0
        )

        route.id = "updated"
        XCTAssertEqual(route.id, "updated")
    }

    func testNameMutation() {
        var route = Route(
            id: "test",
            name: "Original Name",
            fileName: "Test",
            updateInterval: 5.0
        )

        route.name = "Updated Name"
        XCTAssertEqual(route.name, "Updated Name")
    }

    func testFileNameMutation() {
        var route = Route(
            id: "test",
            name: "Test",
            fileName: "OriginalFile",
            updateInterval: 5.0
        )

        route.fileName = "UpdatedFile"
        XCTAssertEqual(route.fileName, "UpdatedFile")
    }

    func testUpdateIntervalMutation() {
        var route = Route(
            id: "test",
            name: "Test",
            fileName: "Test",
            updateInterval: 5.0
        )

        route.updateInterval = 10.0
        XCTAssertEqual(route.updateInterval, 10.0)
    }

    // MARK: - Common Use Cases

    func testWalkingRoute() {
        let walkingRoute = Route(
            id: "morning-walk",
            name: "Morning Walk",
            fileName: "MorningWalk",
            updateInterval: 2.0  // Slower update for walking speed
        )

        XCTAssertEqual(walkingRoute.id, "morning-walk")
        XCTAssertEqual(walkingRoute.updateInterval, 2.0)
    }

    func testDrivingRoute() {
        let drivingRoute = Route(
            id: "highway-drive",
            name: "Highway Drive",
            fileName: "HighwayDrive",
            updateInterval: 0.5  // Faster update for driving speed
        )

        XCTAssertEqual(drivingRoute.id, "highway-drive")
        XCTAssertEqual(drivingRoute.updateInterval, 0.5)
    }

    func testBicycleRoute() {
        let bikeRoute = Route(
            id: "bike-commute",
            name: "Bike Commute",
            fileName: "BikeCommute",
            updateInterval: 1.0
        )

        XCTAssertEqual(bikeRoute.name, "Bike Commute")
        XCTAssertEqual(bikeRoute.updateInterval, 1.0)
    }
}
