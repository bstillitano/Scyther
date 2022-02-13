//
//  File.swift
//
//
//  Created by Brandon Stillitano on 13/2/22.
//

import Foundation
import UIKit

protocol SearchBarDelegate: AnyObject {
    func searchBar(_ searchBar: SearchBar?, didPressDoneButton button: UIButton?)
    func searchBar(_ searchBar: SearchBar?, didSelectRange range: Range<String.Index>?)
    func searchBar(_ searchBar: SearchBar?, didFindRanges ranges: [Range<String.Index>]?)
}

protocol SearchBarDataSource: AnyObject {
    var searchableString: String? { get }
}

class SearchBar: UIView {
    // MARK: - UI Elements
    private lazy var textField: UITextField = {
        let value: UITextField = UITextField()
        value.placeholder = placeholder
        value.borderStyle = .roundedRect
        value.translatesAutoresizingMaskIntoConstraints = false
        value.addTarget(self, action: #selector(textFieldDidChange(_:)), for: .editingChanged)
        value.rightView = counterLabel
        value.rightViewMode = .always
        return value
    }()
    private lazy var counterLabel: UILabel = {
        let value: UILabel = UILabel()
        value.textColor = .systemGray
        value.textAlignment = .center
        value.text = "            "
        value.font = .systemFont(ofSize: 12.0)
        value.adjustsFontSizeToFitWidth = true
        return value
    }()
    private lazy var previousButton: UIButton = {
        let value: UIButton = UIButton()
        value.setImage(UIImage(systemImage: "arrow.up"), for: .normal)
        value.addTarget(self, action: #selector(didPressPreviousButton), for: .touchUpInside)
        value.translatesAutoresizingMaskIntoConstraints = false
        value.isEnabled = false
        return value
    }()
    private lazy var nextButton: UIButton = {
        let value: UIButton = UIButton()
        value.setImage(UIImage(systemImage: "arrow.down"), for: .normal)
        value.addTarget(self, action: #selector(didPressNextButton), for: .touchUpInside)
        value.translatesAutoresizingMaskIntoConstraints = false
        value.isEnabled = false
        return value
    }()
    private lazy var doneButton: UIButton = {
        let value: UIButton = UIButton(type: .system)
        value.setTitle("Done", for: .normal)
        value.addTarget(self, action: #selector(didPressDoneButton), for: .touchUpInside)
        value.translatesAutoresizingMaskIntoConstraints = false
        return value
    }()

    // MARK: - Data
    var placeholder: String? = "Search..." {
        didSet {
            textField.placeholder = placeholder
        }
    }
    var ranges: [Range<String.Index>]? = nil {
        didSet {
            delegate?.searchBar(self, didFindRanges: dataSource?.searchableString?.ranges(of: textField.text ?? ""))
            Task { @MainActor in
                guard let selectedRange = selectedRange else {
                    counterLabel.text = nil
                    return
                }
                counterLabel.text = ranges?.isEmpty ?? true ? nil : "\((ranges?.firstIndex(of: selectedRange) ?? 0) + 1)/\(ranges?.count ?? 0)  "
            }
        }
    }
    var selectedRange: Range<String.Index>? = nil {
        didSet {
            Task { @MainActor in
                previousButton.isEnabled = selectedRange != ranges?.first
                nextButton.isEnabled = selectedRange != ranges?.last
                guard let selectedRange = selectedRange else {
                    counterLabel.text = nil
                    return
                }
                counterLabel.text = ranges?.isEmpty ?? true ? nil : "\((ranges?.firstIndex(of: selectedRange) ?? 0) + 1)/\(ranges?.count ?? 0)  "
            }
            delegate?.searchBar(self, didSelectRange: selectedRange)
        }
    }

    // MARK: - Constraints
    private var subviewConstraints: [NSLayoutConstraint] = []

    // MARK: - Delegate
    weak var delegate: SearchBarDelegate?
    weak var dataSource: SearchBarDataSource?

    // MARK: - Init
    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemBackground

        //Setup Interface
        setupUI()
        setupConstraints()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        addSubview(textField)
        addSubview(previousButton)
        addSubview(nextButton)
        addSubview(doneButton)
    }

    private func setupConstraints() {
        // Clear Constraints
        NSLayoutConstraint.deactivate(subviewConstraints)
        subviewConstraints.removeAll()

        // Setup Priorities
        doneButton.setContentHuggingPriority(.required, for: .horizontal)
        previousButton.setContentHuggingPriority(.required, for: .horizontal)
        nextButton.setContentHuggingPriority(.required, for: .horizontal)
        doneButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        previousButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        nextButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        subviewConstraints.append(doneButton
            .trailingAnchor
            .constraint(equalTo: layoutMarginsGuide.trailingAnchor))
        subviewConstraints.append(nextButton
            .trailingAnchor
            .constraint(equalTo: doneButton.leadingAnchor,
                        constant: -16))
        subviewConstraints.append(previousButton
            .trailingAnchor
            .constraint(equalTo: nextButton.leadingAnchor,
                        constant: -16))
        subviewConstraints.append(textField
            .trailingAnchor
            .constraint(equalTo: previousButton.leadingAnchor,
                        constant: -16))
        subviewConstraints.append(textField
            .leadingAnchor
            .constraint(equalTo: layoutMarginsGuide.leadingAnchor))
        subviewConstraints.append(doneButton
            .centerYAnchor
            .constraint(equalTo: centerYAnchor))
        subviewConstraints.append(previousButton
            .centerYAnchor
            .constraint(equalTo: centerYAnchor))
        subviewConstraints.append(nextButton
            .centerYAnchor
            .constraint(equalTo: centerYAnchor))
        subviewConstraints.append(textField
            .topAnchor
            .constraint(equalTo: topAnchor,
                        constant: 8))
        subviewConstraints.append(textField
            .bottomAnchor
            .constraint(equalTo: bottomAnchor,
                        constant: -8))

        NSLayoutConstraint.activate(subviewConstraints)
    }

    // MARK: - Overrides
    override var isUserInteractionEnabled: Bool {
        get {
            return true
        }
        set {
            //Do nothing
        }
    }
}

// MARK: - Button Actions
extension SearchBar {
    @objc
    private func didPressDoneButton() {
        textField.text = nil
        ranges = nil
        selectedRange = nil
        delegate?.searchBar(self, didPressDoneButton: doneButton)
    }

    @objc
    private func didPressNextButton() {
        guard let ranges = ranges,
            let selectedRange = selectedRange,
            let selectedIndex = ranges.firstIndex(of: selectedRange),
            ranges.indices.contains(selectedIndex + 1) else {
            return
        }
        self.selectedRange = ranges[selectedIndex + 1]
    }

    @objc
    private func didPressPreviousButton() {
        guard let ranges = ranges,
            let selectedRange = selectedRange,
            let selectedIndex = ranges.firstIndex(of: selectedRange),
            ranges.indices.contains(selectedIndex - 1) else {
            return
        }
        self.selectedRange = ranges[selectedIndex - 1]
    }
}

// MARK: - Helper Functions
extension SearchBar {
    @objc
    func textFieldDidChange(_ textField: UITextField) {
        ranges = dataSource?.searchableString?.ranges(of: textField.text ?? "")
        selectedRange = ranges?.first
    }
}
