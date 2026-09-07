//
//  AccessibilityAuditorTestClock.swift
//  ScytherTests
//

@testable import Scyther
import Foundation

extension AccessibilityAuditor {

    /// An auditor whose wall-clock budget can never trip.
    ///
    /// ``AccessibilityAuditor/budget`` bounds a pass at 0.25s of wall clock so a pathological
    /// hierarchy cannot hang the app. That is right in production and wrong in a unit test that
    /// asserts *what the walk found*: the result then depends on how fast the machine was, and a
    /// slow machine turns a correctness test into a timing test that reports "found nothing" as a
    /// defect in the checks.
    ///
    /// That is not hypothetical. On CI, the first audit in the process pays the accessibility
    /// runtime's one-time initialisation — a single fixture with one element took 26 seconds — and
    /// blew the budget before reaching its element, so
    /// `testASyntheticElementOverAViewWithNoTextViewsIsStillMeasured` reported zero candidates.
    /// It had been passing only because the test that ran before it happened to warm the runtime
    /// up first; the moment that test started skipping, this one started failing.
    ///
    /// Freezing the clock removes the budget from every test that is not about the budget. The
    /// budget's own behaviour keeps its dedicated coverage, in
    /// `testAWalkThatRunsOutOfTimeStopsAndSaysSo` and
    /// `testAWalkInsideTheBudgetIsNotReportedAsTruncated`, which drive this same seam deliberately
    /// — a test that assigns ``AccessibilityAuditor/now`` after calling this simply wins, as it
    /// should.
    ///
    /// - Returns: An auditor that believes no time ever passes.
    static func unbudgeted() -> AccessibilityAuditor {
        var auditor = AccessibilityAuditor()
        let frozen = Date()
        auditor.now = { frozen }
        return auditor
    }
}
