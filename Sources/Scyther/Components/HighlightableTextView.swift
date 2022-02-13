//
//  File.swift
//
//
//  Created by Brandon Stillitano on 12/2/22.
//

import UIKit

class HighlightableTextView: UITextView {
    // MARK: - Data
    var attributes: [NSAttributedString.Key: Any]?
    var highlightedAttributes: [NSAttributedString.Key: Any]?
    var focusedAttributes: [NSAttributedString.Key: Any]?
    var highlightedRanges: [Range<String.Index>]? = nil {
        didSet {
            highlightRanges()
        }
    }
    var focusedRange: Range<String.Index>? {
        didSet {
            highlightRanges()
        }
    }

    override var text: String! {
        get {
            return super.text
        }
        set {
            super.text = newValue
            attributedText = NSMutableAttributedString(string: newValue,
                                                       attributes: attributes)
        }
    }

    private func highlightRanges() {
        Task { @MainActor in
            let text = NSMutableAttributedString(string: text,
                                                 attributes: attributes)
            for range in highlightedRanges ?? [] {
                text.addAttributes(highlightedAttributes ?? [:],
                                   range: range.nsRange)
            }
            if let focusedRange = focusedRange {
                text.addAttributes(focusedAttributes ?? [:],
                                   range: focusedRange.nsRange)
            }
            attributedText = text
            
            if let focusedRange = focusedRange {
                scrollRangeToVisible(focusedRange.nsRange)
            }
        }
    }
}
