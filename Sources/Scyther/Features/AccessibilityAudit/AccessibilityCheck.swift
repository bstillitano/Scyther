//
//  AccessibilityCheck.swift
//  Scyther
//
//  Created by Brandon Stillitano on 6/9/2026.
//

import Foundation

/// One thing the audit looks for.
///
/// Each check is switched on and off on its own, and a check that is off is not run at all —
/// which is why the report names the checks that did not run: "no findings" and "nothing was
/// looked at" must never read the same way.
enum AccessibilityCheck: String, CaseIterable, Sendable, Identifiable {
    /// An element VoiceOver cannot name.
    case missingLabel
    /// A target smaller than a finger.
    case touchTarget
    /// Text too close in colour to what is behind it.
    case contrast

    /// The raw value, so SwiftUI can key rows on it.
    var id: String { rawValue }

    /// The check's name, as the report and the settings screen show it.
    var title: String {
        switch self {
        case .missingLabel: return localized("Missing Labels")
        case .touchTarget: return localized("Touch Targets")
        case .contrast: return localized("Contrast")
        }
    }

    /// Where this check's on/off state is persisted in `UserDefaults.scyther`.
    var defaultsKey: String {
        switch self {
        case .missingLabel: return "Scyther_accessibility_audit_missing_labels"
        case .touchTarget: return "Scyther_accessibility_audit_touch_targets"
        case .contrast: return "Scyther_accessibility_audit_contrast"
        }
    }
}

/// How much a finding matters.
///
/// Two levels, not five. A finding is either something a user cannot work around — a control
/// with no name — or something that might be deliberate, and a scale finer than that would be
/// a judgement the toolkit is not in a position to make.
enum AccessibilitySeverity: Int, Comparable, Sendable {
    /// Worth looking at; may be deliberate, or may be an estimate.
    case warning = 0
    /// Broken for somebody.
    case error = 1

    static func < (lhs: AccessibilitySeverity, rhs: AccessibilitySeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
