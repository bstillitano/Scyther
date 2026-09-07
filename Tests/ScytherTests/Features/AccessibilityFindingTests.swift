//
//  AccessibilityFindingTests.swift
//  ScytherTests
//
//  Created by Brandon Stillitano on 6/9/2026.
//

@testable import Scyther
import XCTest

final class AccessibilityFindingTests: XCTestCase {

    func testEveryCheckHasItsOwnDefaultsKey() {
        let keys = Set(AccessibilityCheck.allCases.map(\.defaultsKey))
        XCTAssertEqual(keys.count, AccessibilityCheck.allCases.count)
        XCTAssertTrue(keys.allSatisfy { $0.hasPrefix("Scyther_accessibility_audit_") })
    }

    /// An error sorts above a warning, so the report can lead with what matters.
    func testAnErrorOutranksAWarning() {
        XCTAssertTrue(AccessibilitySeverity.error > AccessibilitySeverity.warning)
    }

    /// Two findings about the same element are still two findings.
    func testFindingsAreIdentifiedIndividually() {
        let frame = CGRect(x: 0, y: 0, width: 10, height: 10)
        let first = AccessibilityFinding(check: .touchTarget, severity: .error, frame: frame,
                                         elementName: "Close", detail: "10.0 × 10.0pt")
        let second = AccessibilityFinding(check: .touchTarget, severity: .error, frame: frame,
                                          elementName: "Close", detail: "10.0 × 10.0pt")
        XCTAssertNotEqual(first.id, second.id)
    }
}
