//
//  FeatureToggleStateTests.swift
//  ScytherTests
//
//  Created by Brandon Stillitano on 20/12/2025.
//

#if !os(macOS)
@testable import Scyther
import XCTest

final class FeatureToggleStateTests: XCTestCase {

    func testAllCasesOrderIsTrueFalseRemote() {
        XCTAssertEqual(FeatureToggleState.allCases, [.on, .off, .remote])
    }

    func testDisplayNames() {
        XCTAssertEqual(FeatureToggleState.on.displayName, "True")
        XCTAssertEqual(FeatureToggleState.off.displayName, "False")
        XCTAssertEqual(FeatureToggleState.remote.displayName, "Remote")
    }

    func testIdentifiableIdMatchesRawValue() {
        for state in FeatureToggleState.allCases {
            XCTAssertEqual(state.id, state.rawValue)
        }
    }
}
#endif
