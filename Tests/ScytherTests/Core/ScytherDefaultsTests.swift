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
        let key = "Scyther_fps_counter_enabled"
        source.set(true, forKey: key)

        // First run: the key moves across as usual.
        ScytherDefaults.migrate(from: source, to: destination)

        // Re-seed the source with the *same* value it had originally, but give the
        // destination a *different* value than what the source would supply. A second
        // migration run must leave the destination's value alone - if `migrate` ever started
        // unconditionally overwriting, this is what would catch it - while still sweeping the
        // re-seeded key out of the source.
        source.set(true, forKey: key)
        destination.set(false, forKey: key)

        ScytherDefaults.migrate(from: source, to: destination)

        XCTAssertFalse(destination.bool(forKey: key), "the destination's existing value must survive a second migration run")
        XCTAssertNil(source.object(forKey: key), "the source key must still be removed on the second run")
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
    //
    // `UserDefaults.scyther` is a `nonisolated(unsafe) static let`, backed by the real,
    // on-disk `com.scyther.settings` suite - not a throwaway suite like `source`/`destination`
    // above. Because it is a `static`, the *first* access anywhere in this test binary's
    // process runs `ScytherDefaults.makeStore()`'s one-time migration against the real
    // `UserDefaults.standard`, once, for the lifetime of the process. Any `Scyther*` fixture a
    // test seeds into `UserDefaults.standard` *after* that first access will never be picked
    // up by a subsequent migration - it will just sit there looking like it "vanished" from
    // the destination. Don't seed `Scyther*` keys into `UserDefaults.standard` expecting this
    // store to observe them; use the `source`/`destination` throwaway suites for migration
    // behaviour instead.
    //
    // The two tests below are the only ones in this file that touch the real suite, and
    // nothing else in the suite ever cleans it. They must therefore leave it exactly as they
    // found it - including when an assertion inside them fails - so state never leaks across
    // test runs on the same simulator.

    func testScytherStoreIsNotTheStandardStore() {
        XCTAssertFalse(UserDefaults.scyther === UserDefaults.standard)
    }

    func testScytherStoreWritesAreInvisibleToStandard() {
        let key = "Scyther_isolation_probe"

        // Registered before the write, so it still runs - and removes the probe key - even if
        // an assertion below fails or a future edit adds a path that returns early.
        addTeardownBlock {
            UserDefaults.scyther.removeObject(forKey: key)
        }

        UserDefaults.scyther.set(true, forKey: key)

        XCTAssertTrue(UserDefaults.scyther.bool(forKey: key))
        XCTAssertNil(UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?[key])
    }
}
#endif
