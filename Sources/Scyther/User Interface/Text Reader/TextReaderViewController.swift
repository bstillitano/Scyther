//
//  TextReaderViewController.swift
//
//
//  Created by Brandon Stillitano on 28/12/20.
//

import UIKit

class TextReaderViewController: UIViewController {
    // MARK: - UI Elements
    private lazy var textView: HighlightableTextView = {
        let value: HighlightableTextView = HighlightableTextView()
        value.attributes = [.foregroundColor: UIColor.label,
                                .font: UIFont.systemFont(ofSize: 13.0)]
        value.highlightedAttributes = [.foregroundColor: UIColor.black,
                                           .backgroundColor: UIColor.yellow,
                                           .font: UIFont.systemFont(ofSize: 13.0)]
        value.focusedAttributes = [.foregroundColor: UIColor.black,
                                       .backgroundColor: UIColor.orange,
                                       .font: UIFont.systemFont(ofSize: 13.0)]
        value.text = ""
        value.isSelectable = true
        value.isEditable = false
        value.textColor = .green
        value.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        value.translatesAutoresizingMaskIntoConstraints = false
        return value
    }()
    private lazy var searchButton: UIBarButtonItem = {
        let value: UIBarButtonItem = UIBarButtonItem(barButtonSystemItem: .search, target: self, action: #selector(didPressSearchButton))
        return value
    }()
    private lazy var shareButton: UIBarButtonItem = {
        let value = UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(shareText))
        return value
    }()
    private lazy var searchBar: SearchBar = {
        let value: SearchBar = SearchBar()
        value.delegate = self
        value.dataSource = self
        value.isHidden = true
        value.translatesAutoresizingMaskIntoConstraints = false
        return value
    }()

    // MARK: - Data
    var text: String? = nil {
        didSet {
            textView.text = text
        }
    }
    private var isSearching: Bool = false {
        didSet {
            Task { @MainActor in
                searchBar.isHidden = !isSearching
                setupNavigationBar()
            }
        }
    }

    // MARK: - Constraints
    private var textViewConstraints: [NSLayoutConstraint] = []
    private var searchBarConstraints: [NSLayoutConstraint] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        
        /// Setup interface
        setupUI()
        setupNavigationBar()
        setupConstraints()
    }

    private func setupNavigationBar() {
        navigationItem.setRightBarButtonItems(isSearching ? [] : [searchButton, shareButton], animated: true)
    }

    private func setupUI() {
        /// Setup Text View
        textView.font = .systemFont(ofSize: 13.0)
        textView.isEditable = false
        view.addSubview(textView)

        /// Setup Search Bar
        navigationController?.view.addSubview(searchBar)
    }

    private func setupConstraints() {
        // Clear Constraints
        NSLayoutConstraint.deactivate(textViewConstraints)
        NSLayoutConstraint.deactivate(searchBarConstraints)
        textViewConstraints.removeAll()
        searchBarConstraints.removeAll()

        // Setup Search Bar Constraints
        searchBarConstraints.append(searchBar
            .leadingAnchor
            .constraint(equalTo: navigationController?.view.leadingAnchor ?? view.leadingAnchor))
        searchBarConstraints.append(searchBar
            .trailingAnchor
            .constraint(equalTo: navigationController?.view.trailingAnchor ?? view.trailingAnchor))
        searchBarConstraints.append(searchBar
            .topAnchor
            .constraint(equalTo: navigationController?.view.topAnchor ?? view.topAnchor))
        searchBarConstraints.append(searchBar
            .bottomAnchor
            .constraint(equalTo: navigationController?.navigationBar.bottomAnchor ?? view.bottomAnchor))

        // Setup Text View Constraints
        textViewConstraints.append(textView
            .topAnchor
            .constraint(equalTo: view.layoutMarginsGuide.topAnchor))
        textViewConstraints.append(textView
            .leadingAnchor
            .constraint(equalTo: view.layoutMarginsGuide.leadingAnchor))
        textViewConstraints.append(textView
            .trailingAnchor
            .constraint(equalTo: view.layoutMarginsGuide.trailingAnchor))
        textViewConstraints.append(textView
            .bottomAnchor
            .constraint(equalTo: view.layoutMarginsGuide.bottomAnchor))

        NSLayoutConstraint.activate(searchBarConstraints)
        NSLayoutConstraint.activate(textViewConstraints)
    }

    @objc
    private func shareText() {
        let viewController = UIActivityViewController(activityItems: [text ?? ""],
                                                      applicationActivities: nil)
        self.present(viewController, animated: true)
    }
    
    @objc
    private func didPressSearchButton() {
        isSearching = true
    }
}

// MARK: - SearchBarDataSource
extension TextReaderViewController: SearchBarDataSource {
    var searchableString: String? {
        return textView.text
    }
}

// MARK: - SearchBarDelegate
extension TextReaderViewController: SearchBarDelegate {
    func searchBar(_ searchBar: SearchBar?, didFindRanges ranges: [Range<String.Index>]?) {
        textView.highlightedRanges = ranges
    }

    func searchBar(_ searchBar: SearchBar?, didPressDoneButton button: UIButton?) {
        isSearching = false
        textView.highlightedRanges = nil
        textView.focusedRange = nil
    }

    func searchBar(_ searchBar: SearchBar?, didSelectRange range: Range<String.Index>?) {
        textView.focusedRange = range
    }
}

