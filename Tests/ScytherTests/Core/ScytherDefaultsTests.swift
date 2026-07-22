//
//  ScytherDefaultsTests.swift
//  ScytherTests
//
//  Created by Brandon Stillitano on 22/7/2026.
//

#if !os(macOS)
@testable import Scyther
import XCTest

final class ScytherDefaultsTests: XCTestCase {
    private let sourceSuite = "com.scyther.tests.source"
    private let destinationSuite = "com.scyther.tests.destination"
    private var source: UserDefaults!
    private var destination: UserDefaults!

    override func setUp() {
        super.setUp()
        wipeSuites()
        source = UserDefaults(suiteName: sourceSuite)
        destination = UserDefaults(suiteName: destinationSuite)
    }

    override func tearDown() {
        source = nil
        destination = nil
        wipeSuites()
        super.tearDown()
    }

    private func wipeSuites() {
        UserDefaults.standard.removePersistentDomain(forName: sourceSuite)
        UserDefaults.standard.removePersistentDomain(forName: destinationSuite)
    }

    // MARK: - Constants

    func testSuiteNameIsStable() {
        XCTAssertEqual(ScytherDefaults.suiteName, "com.scyther.settings")
    }

    func testMigrationKeyIsStable() {
        XCTAssertEqual(ScytherDefaults.migrationKey, "Scyther.Defaults.DidMigrateFromStandard")
    }

    // MARK: - migrate(from:to:)

    func testMigrationCopiesPrefixedKeysToDestination() {
        source.set(true, forKey: "Scyther_grid_overlay_enabled")
        source.set("preset-a", forKey: "Scyther_Location_Spoofing_Route_Id")

        ScytherDefaults.migrate(from: source, to: destination)

        XCTAssertTrue(destination.bool(forKey: "Scyther_grid_overlay_enabled"))
        XCTAssertEqual(destination.string(forKey: "Scyther_Location_Spoofing_Route_Id"), "preset-a")
    }

    func testMigrationRemovesPrefixedKeysFromSource() {
        source.set(true, forKey: "Scyther_grid_overlay_enabled")

        ScytherDefaults.migrate(from: source, to: destination)

        XCTAssertNil(source.object(forKey: "Scyther_grid_overlay_enabled"))
    }

    func testMigrationIgnoresKeysWithoutThePrefix() {
        source.set("hunter2", forKey: "user_session_token")

        ScytherDefaults.migrate(from: source, to: destination)

        XCTAssertEqual(source.string(forKey: "user_session_token"), "hunter2")
        XCTAssertNil(destination.object(forKey: "user_session_token"))
    }

    func testMigrationMatchesPrefixCaseInsensitively() {
        source.set(1, forKey: "scyther.servers.currentId")
        source.set(2, forKey: "SCYTHER_shouting_key")

        ScytherDefaults.migrate(from: source, to: destination)

        XCTAssertEqual(destination.integer(forKey: "scyther.servers.currentId"), 1)
        XCTAssertEqual(destination.integer(forKey: "SCYTHER_shouting_key"), 2)
    }

    func testMigrationNeverOverwritesAnExistingDestinationValue() {
        source.set("stale", forKey: "Scyther_appearance_color_scheme")
        destination.set("fresh", forKey: "Scyther_appearance_color_scheme")

        ScytherDefaults.migrate(from: source, to: destination)

        XCTAssertEqual(destination.string(forKey: "Scyther_appearance_color_scheme"), "fresh")
        XCTAssertNil(source.object(forKey: "Scyther_appearance_color_scheme"))
    }

    func testMigrationIsIdempotent() {
        source.set(true, forKey: "Scyther_fps_counter_enabled")

        ScytherDefaults.migrate(from: source, to: destination)
        destination.set(false, forKey: "Scyther_fps_counter_enabled")
        ScytherDefaults.migrate(from: source, to: destination)

        XCTAssertFalse(destination.bool(forKey: "Scyther_fps_counter_enabled"))
    }

    // MARK: - migrateIfNeeded(from:to:)

    func testMigrateIfNeededSetsTheMigrationFlag() {
        ScytherDefaults.migrateIfNeeded(from: source, to: destination)

        XCTAssertTrue(destination.bool(forKey: ScytherDefaults.migrationKey))
    }

    func testMigrateIfNeededRunsOnlyOnce() {
        ScytherDefaults.migrateIfNeeded(from: source, to: destination)

        // Seed the source *after* the first run. A second call must not pick it up.
        source.set(true, forKey: "Scyther_grid_overlay_enabled")
        ScytherDefaults.migrateIfNeeded(from: source, to: destination)

        XCTAssertNil(destination.object(forKey: "Scyther_grid_overlay_enabled"))
        XCTAssertTrue(source.bool(forKey: "Scyther_grid_overlay_enabled"))
    }

    // MARK: - Store

    func testScytherStoreIsNotTheStandardStore() {
        XCTAssertFalse(UserDefaults.scyther === UserDefaults.standard)
    }

    func testScytherStoreWritesAreInvisibleToStandard() {
        let key = "Scyther_isolation_probe"
        UserDefaults.scyther.set(true, forKey: key)
        defer { UserDefaults.scyther.removeObject(forKey: key) }

        XCTAssertTrue(UserDefaults.scyther.bool(forKey: key))
        XCTAssertNil(UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?[key])
    }
}
#endif
