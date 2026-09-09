//
//  TextCarryingViewTests.swift
//  ScytherTests
//

@testable import Scyther
import UIKit
import XCTest

/// The whitelist the walker and the detail page both read text through.
///
/// It exists so a fourth text-carrying type is added once rather than three times; these cover
/// all three cases against all three properties, which is what none of the three copies had.
@MainActor
final class TextCarryingViewTests: XCTestCase {

    // MARK: - Classification

    func testAPlainViewCarriesNoText() {
        XCTAssertNil(TextCarryingView(UIView()))
    }

    func testALabelIsClassifiedAsALabel() {
        guard case .label = TextCarryingView(UILabel()) else {
            return XCTFail("a UILabel carries text")
        }
    }

    func testAButtonIsClassifiedAsAButton() {
        guard case .button = TextCarryingView(UIButton(type: .system)) else {
            return XCTFail("a UIButton carries text")
        }
    }

    func testATextFieldIsClassifiedAsATextField() {
        guard case .textField = TextCarryingView(UITextField()) else {
            return XCTFail("a UITextField carries text")
        }
    }

    // MARK: - Text

    func testALabelReportsItsText() {
        let label = UILabel()
        label.text = "Total"
        XCTAssertEqual(TextCarryingView(label)?.text, "Total")
    }

    /// `currentTitle`, not `titleLabel?.text`, so a button showing a state-specific title still
    /// answers with what is on screen.
    func testAButtonReportsTheTitleItIsCurrentlyShowing() {
        let button = UIButton(type: .system)
        button.setTitle("Buy", for: .normal)
        XCTAssertEqual(TextCarryingView(button)?.text, "Buy")
    }

    func testATextFieldReportsItsText() {
        let field = UITextField()
        field.text = "hello@example.com"
        XCTAssertEqual(TextCarryingView(field)?.text, "hello@example.com")
    }

    /// The property this must never reach for. An accessibility label is the richer answer and is
    /// exactly what forces `UIAccessibility` to compute a subtree — the walk that hung the app in
    /// 4.3.0.
    func testAnEmptyLabelDoesNotFallBackToItsAccessibilityLabel() {
        let label = UILabel()
        label.accessibilityLabel = "Total, in dollars"
        XCTAssertNil(TextCarryingView(label)?.text)
    }

    // MARK: - Font and colour

    func testALabelReportsItsFontAndTextColour() {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 19)
        label.textColor = .red
        XCTAssertEqual(TextCarryingView(label)?.font?.pointSize, 19)
        XCTAssertEqual(TextCarryingView(label)?.textColour, .red)
    }

    func testAButtonReportsItsTitleLabelsFontAndItsNormalTitleColour() {
        let button = UIButton(type: .custom)
        button.setTitle("Buy", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 21)
        button.setTitleColor(.green, for: .normal)
        XCTAssertEqual(TextCarryingView(button)?.font?.pointSize, 21)
        XCTAssertEqual(TextCarryingView(button)?.textColour, .green)
    }

    func testATextFieldReportsItsFontAndTextColour() {
        let field = UITextField()
        field.font = UIFont.systemFont(ofSize: 13)
        field.textColor = .blue
        XCTAssertEqual(TextCarryingView(field)?.font?.pointSize, 13)
        XCTAssertEqual(TextCarryingView(field)?.textColour, .blue)
    }

    // MARK: - The accessibility guarantee

    /// The never-touch-accessibility rule covers **all three** properties, not just `text`.
    ///
    /// `font` and `textColour` are read from a live view by ``ViewDetailViewModel`` on every
    /// detail page, and a regression shaped like `label.font ?? somethingAccessibility` there
    /// would reach `UIAccessibility` on a view the walk had deliberately left alone. Every
    /// property is read on a spy that counts, and each is left unset so a `??` fallback cannot
    /// short-circuit past its own right-hand side — the same reason
    /// `ViewHierarchyWalkerTests` gives its spies no text.
    func testReadingEveryPropertyTouchesNoAccessibilityMember() {
        let labelSpy = AccessibilitySpyLabel()
        let buttonSpy = AccessibilitySpyButton(type: .custom)
        let fieldSpy = AccessibilitySpyTextField()

        for view in [labelSpy as UIView, buttonSpy, fieldSpy] {
            let carrying = TextCarryingView(view)
            _ = carrying?.text
            _ = carrying?.font
            _ = carrying?.textColour
        }

        XCTAssertEqual(labelSpy.accessibilityReads, 0)
        XCTAssertEqual(buttonSpy.accessibilityReads, 0)
        XCTAssertEqual(fieldSpy.accessibilityReads, 0)
    }
}

/// Counts every accessibility member a text read could plausibly reach for, on a `UILabel`.
private final class AccessibilitySpyLabel: UILabel {
    var accessibilityReads = 0

    override var isAccessibilityElement: Bool {
        get { accessibilityReads += 1; return super.isAccessibilityElement }
        set { super.isAccessibilityElement = newValue }
    }

    override var accessibilityLabel: String? {
        get { accessibilityReads += 1; return super.accessibilityLabel }
        set { super.accessibilityLabel = newValue }
    }

    override var accessibilityValue: String? {
        get { accessibilityReads += 1; return super.accessibilityValue }
        set { super.accessibilityValue = newValue }
    }

    override var accessibilityIdentifier: String? {
        get { accessibilityReads += 1; return super.accessibilityIdentifier }
        set { super.accessibilityIdentifier = newValue }
    }

    override var accessibilityAttributedLabel: NSAttributedString? {
        get { accessibilityReads += 1; return super.accessibilityAttributedLabel }
        set { super.accessibilityAttributedLabel = newValue }
    }
}

/// The same instrumentation, on a `UIButton`.
private final class AccessibilitySpyButton: UIButton {
    var accessibilityReads = 0

    override var isAccessibilityElement: Bool {
        get { accessibilityReads += 1; return super.isAccessibilityElement }
        set { super.isAccessibilityElement = newValue }
    }

    override var accessibilityLabel: String? {
        get { accessibilityReads += 1; return super.accessibilityLabel }
        set { super.accessibilityLabel = newValue }
    }

    override var accessibilityValue: String? {
        get { accessibilityReads += 1; return super.accessibilityValue }
        set { super.accessibilityValue = newValue }
    }

    override var accessibilityIdentifier: String? {
        get { accessibilityReads += 1; return super.accessibilityIdentifier }
        set { super.accessibilityIdentifier = newValue }
    }

    override var accessibilityAttributedLabel: NSAttributedString? {
        get { accessibilityReads += 1; return super.accessibilityAttributedLabel }
        set { super.accessibilityAttributedLabel = newValue }
    }
}

/// The same instrumentation, on a `UITextField`.
private final class AccessibilitySpyTextField: UITextField {
    var accessibilityReads = 0

    override var isAccessibilityElement: Bool {
        get { accessibilityReads += 1; return super.isAccessibilityElement }
        set { super.isAccessibilityElement = newValue }
    }

    override var accessibilityLabel: String? {
        get { accessibilityReads += 1; return super.accessibilityLabel }
        set { super.accessibilityLabel = newValue }
    }

    override var accessibilityValue: String? {
        get { accessibilityReads += 1; return super.accessibilityValue }
        set { super.accessibilityValue = newValue }
    }

    override var accessibilityIdentifier: String? {
        get { accessibilityReads += 1; return super.accessibilityIdentifier }
        set { super.accessibilityIdentifier = newValue }
    }

    override var accessibilityAttributedLabel: NSAttributedString? {
        get { accessibilityReads += 1; return super.accessibilityAttributedLabel }
        set { super.accessibilityAttributedLabel = newValue }
    }
}
