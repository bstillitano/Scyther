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
}
