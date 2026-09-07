//
//  AccessibilityFinding.swift
//  Scyther
//
//  Created by Brandon Stillitano on 6/9/2026.
//

import CoreGraphics
import Foundation

/// One defect the audit found, on one element.
///
/// Carries what was measured rather than only what failed: `32.0 × 32.0pt` tells the developer
/// how far off the target is, where "too small" tells them nothing they can act on.
struct AccessibilityFinding: Identifiable, Sendable, Equatable {
    /// A fresh identity per finding. Two findings about one element are still two findings.
    let id: UUID

    /// Which check produced it.
    let check: AccessibilityCheck

    /// How much it matters.
    let severity: AccessibilitySeverity

    /// The element's frame in window coordinates, which is where the overlay draws.
    let frame: CGRect

    /// What to call the element: its accessibility label, or its type and position when it has
    /// none — which is precisely the case the missing-label check exists to report.
    let elementName: String

    /// The measurement, already localised and formatted.
    let detail: String

    /// Creates a finding.
    ///
    /// - Parameters:
    ///   - check: The check that produced it.
    ///   - severity: How much it matters.
    ///   - frame: The element's frame in window coordinates.
    ///   - elementName: What to call the element in the report.
    ///   - detail: The localised measurement.
    init(check: AccessibilityCheck,
         severity: AccessibilitySeverity,
         frame: CGRect,
         elementName: String,
         detail: String) {
        self.id = UUID()
        self.check = check
        self.severity = severity
        self.frame = frame
        self.elementName = elementName
        self.detail = detail
    }
}
