//
//  UserDefaultsViewModelTests.swift
//  ScytherTests
//
//  Created by Brandon Stillitano on 22/7/2026.
//

#if !os(macOS)
@testable import Scyther
import XCTest

@MainActor
final class UserDefaultsViewModelTests: XCTestCase {
    private let appKey = "scyther_tests_app_only_key"
    private let scytherKey = "Scyther_tests_suite_only_key"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: appKey)
        UserDefaults.scyther.removeObject(forKey: scytherKey)
        super.tearDown()
    }

    func testAppStoreResolvesToStandard() {
        XCTAssertTrue(DefaultsStore.app.defaults === UserDefaults.standard)
    }

    func testScytherStoreResolvesToTheSuite() {
        XCTAssertTrue(DefaultsStore.scyther.defaults === UserDefaults.scyther)
    }

    func testEveryStoreHasATitle() {
        for store in DefaultsStore.allCases {
            XCTAssertFalse(store.title.isEmpty, "\(store) has no title")
        }
    }

    func testAppStoreLoadsKeysFromStandard() async {
        UserDefaults.standard.set("app", forKey: appKey)

        let viewModel = UserDefaultsViewModel(store: .app)
        await viewModel.loadDefaults()

        XCTAssertTrue(viewModel.keyValues.contains { $0.key == appKey })
    }

    func testScytherStoreLoadsKeysFromTheSuite() async {
        UserDefaults.scyther.set("suite", forKey: scytherKey)

        let viewModel = UserDefaultsViewModel(store: .scyther)
        await viewModel.loadDefaults()

        XCTAssertTrue(viewModel.keyValues.contains { $0.key == scytherKey })
    }

    func testScytherStoreDoesNotLeakStandardKeys() async {
        UserDefaults.standard.set("app", forKey: appKey)

        let viewModel = UserDefaultsViewModel(store: .scyther)
        await viewModel.loadDefaults()

        XCTAssertFalse(viewModel.keyValues.contains { $0.key == appKey })
    }

    func testScytherStoreExcludesGlobalDomainKeys() async {
        // AppleLanguages is inherited from NSGlobalDomain. Reading the suite via its
        // persistent domain must not surface it.
        let viewModel = UserDefaultsViewModel(store: .scyther)
        await viewModel.loadDefaults()

        XCTAssertFalse(viewModel.keyValues.contains { $0.key == "AppleLanguages" })
    }

    func testWritesRouteToTheSelectedStore() async {
        let viewModel = UserDefaultsViewModel(store: .scyther)
        viewModel.updateValue("written", forKey: scytherKey)

        XCTAssertEqual(UserDefaults.scyther.string(forKey: scytherKey), "written")
        XCTAssertNil(UserDefaults.standard.string(forKey: scytherKey))
    }

    func testDeletesRouteToTheSelectedStore() async {
        UserDefaults.scyther.set("doomed", forKey: scytherKey)

        let viewModel = UserDefaultsViewModel(store: .scyther)
        await viewModel.loadDefaults()
        viewModel.deleteKey(scytherKey)

        XCTAssertNil(UserDefaults.scyther.object(forKey: scytherKey))
        XCTAssertFalse(viewModel.keyValues.contains { $0.key == scytherKey })
    }
}
#endif
