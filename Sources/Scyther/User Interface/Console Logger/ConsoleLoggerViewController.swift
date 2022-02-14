//
//  File.swift
//
//
//  Created by Brandon Stillitano on 18/1/21.
//

import UIKit
import Foundation

internal class ConsoleLoggerViewController: UIViewController {
    // MARK: - Static Data
    static let SkipWarningDefaultsKey: String = "scyther_console_logger_skip_warnings"

    // MARK: - UI Elements
    private lazy var textView: HighlightableTextView = {
        let value: HighlightableTextView = HighlightableTextView()
        value.delegate = self
        value.attributes = [.foregroundColor: UIColor.green,
                                .font: UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)]
        value.highlightedAttributes = [.foregroundColor: UIColor.black,
                                           .backgroundColor: UIColor.white,
                                           .font: UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)]
        value.focusedAttributes = [.foregroundColor: UIColor.black,
                                       .backgroundColor: UIColor.orange,
                                       .font: UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)]
        value.text = ""
        value.isSelectable = true
        value.isEditable = false
        value.textColor = .green
        value.backgroundColor = .clear
        value.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        value.translatesAutoresizingMaskIntoConstraints = false
        return value
    }()
    private lazy var searchButton: UIBarButtonItem = {
        let value: UIBarButtonItem = UIBarButtonItem(barButtonSystemItem: .search, target: self, action: #selector(didPressSearchButton))
        return value
    }()
    private lazy var pauseButton: UIBarButtonItem = {
        let value: UIBarButtonItem = UIBarButtonItem(image: UIImage(systemImage: "pause.fill"), style: .plain, target: self, action: #selector(didPressPauseButton))
        return value
    }()
    private lazy var scrollToBottomButton: UIButton = {
        let value: UIButton = UIButton()
        value.setImage(UIImage(systemImage: "arrow.down.circle.fill"), for: .normal)
        value.isHidden = true
        value.addTarget(self, action: #selector(didPressScrollToBottom), for: .touchUpInside)
        value.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 48), forImageIn: .normal)
        value.translatesAutoresizingMaskIntoConstraints = false
        return value
    }()
    private lazy var toolbar: UIToolbar = {
        let value: UIToolbar = UIToolbar()
        value.translatesAutoresizingMaskIntoConstraints = false
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
    private var fileHandle: FileHandle!
    private var automaticallyScrollsToBottom: Bool = true {
        didSet {
            Task { @MainActor in
                pauseButton.image = automaticallyScrollsToBottom ? UIImage(systemImage: "pause.fill") : UIImage(systemImage: "play.fill")
            }
        }
    }
    private var queuedValues: [String] = []
    private var isSearching: Bool = false {
        didSet {
            automaticallyScrollsToBottom = !isSearching
            Task { @MainActor in
                searchBar.isHidden = !isSearching
                setupNavigationBar()
            }
        }
    }

    // MARK: - Constraints
    private var subviewConstraints: [NSLayoutConstraint] = []

    // MARK: Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Console Logger"

        commonInit()
    }

    private func commonInit() {
        setupFileHandler()
        setupUI()
        setupNavigationBar()
        setupToolbar()
        setupConstraints()
    }

    private func setupFileHandler() {
        guard let logFileURL = ConsoleLogger.instance.logFileLocation else {
            fatalError()
        }
        fileHandle = FileHandle(forReadingAtPath: logFileURL.path)
        fileHandle.readabilityHandler = { [weak self] handle in
            let data = handle.readData(ofLength: 10_000)
            if let value = String(data: data, encoding: .utf8) {
                self?.logValue(value)
            }
        }
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground
        view.addSubview(textView)
        view.addSubview(scrollToBottomButton)
        navigationController?.view.addSubview(searchBar)
    }

    private func setupNavigationBar() {
        navigationItem.setRightBarButtonItems(isSearching ? [] : [searchButton], animated: true)
    }

    private func setupToolbar() {
        //Setup Buttons
        let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace,
                                            target: nil,
                                            action: nil)
        let shareButton = UIBarButtonItem(image: UIImage(systemImage: "square.and.arrow.up"),
                                          style: .plain,
                                          target: self,
                                          action: #selector(didPressShareButton(_:)))
        let deleteButton = UIBarButtonItem(image: UIImage(systemImage: "trash"),
                                           style: .plain,
                                           target: self,
                                           action: #selector(didPressClearButton))
        toolbar.setItems([deleteButton, flexibleSpace, pauseButton, flexibleSpace, shareButton], animated: false)
        toolbar.isUserInteractionEnabled = true
        view.addSubview(toolbar)
    }

    private func setupConstraints() {
        // Clear Constraints
        NSLayoutConstraint.deactivate(subviewConstraints)
        subviewConstraints.removeAll()

        // Setup Search Bar Constraints
        subviewConstraints.append(searchBar
            .leadingAnchor
            .constraint(equalTo: navigationController?.view.leadingAnchor ?? view.leadingAnchor))
        subviewConstraints.append(searchBar
            .trailingAnchor
            .constraint(equalTo: navigationController?.view.trailingAnchor ?? view.trailingAnchor))
        subviewConstraints.append(searchBar
            .topAnchor
            .constraint(equalTo: navigationController?.view.topAnchor ?? view.topAnchor))
        subviewConstraints.append(searchBar
            .bottomAnchor
            .constraint(equalTo: navigationController?.navigationBar.bottomAnchor ?? view.bottomAnchor))

        // Setup Toolbar Constraints
        subviewConstraints.append(toolbar
            .leadingAnchor
            .constraint(equalTo: view.leadingAnchor))
        subviewConstraints.append(toolbar
            .trailingAnchor
            .constraint(equalTo: view.trailingAnchor))
        subviewConstraints.append(toolbar
            .bottomAnchor
            .constraint(equalTo: view.layoutMarginsGuide.bottomAnchor))

        // Setup Text View Constraints
        subviewConstraints.append(textView
            .topAnchor
            .constraint(equalTo: view.layoutMarginsGuide.topAnchor))
        subviewConstraints.append(textView
            .leadingAnchor
            .constraint(equalTo: view.layoutMarginsGuide.leadingAnchor))
        subviewConstraints.append(textView
            .trailingAnchor
            .constraint(equalTo: view.layoutMarginsGuide.trailingAnchor))
        subviewConstraints.append(textView
            .bottomAnchor
            .constraint(equalTo: toolbar.topAnchor))
        subviewConstraints.append(scrollToBottomButton
            .bottomAnchor
            .constraint(equalTo: toolbar.topAnchor, constant: -16))
        subviewConstraints.append(scrollToBottomButton
            .trailingAnchor
            .constraint(equalTo: view.layoutMarginsGuide.trailingAnchor))
        subviewConstraints.append(scrollToBottomButton
            .widthAnchor
            .constraint(equalToConstant: 48))
        subviewConstraints.append(scrollToBottomButton
            .heightAnchor
            .constraint(equalToConstant: 48))

        NSLayoutConstraint.activate(subviewConstraints)
    }
}

// MARK: - Helper Functions
extension ConsoleLoggerViewController {
    private func logValue(_ text: String) {
        Task { @MainActor [weak self] in
            guard automaticallyScrollsToBottom else {
                queuedValues.append(text)
                return
            }
            queuedValues.forEach { value in
                self?.textView.text.append(text)
            }
            queuedValues.removeAll()
            self?.textView.text.append(text)
            self?.textView.text = String(self?.textView.text.suffix(10000) ?? Substring())
            guard let endIndex: String.Index = self?.textView.text.endIndex else {
                return
            }
            self?.textView.scrollRangeToVisible(NSRange(..<endIndex, in: self?.textView.text ?? ""))
        }
    }
}

// MARK: - UITextViewDelegate
extension ConsoleLoggerViewController: UITextViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !automaticallyScrollsToBottom else {
            scrollToBottomButton.isHidden = true
            return
        }
        Task { @MainActor in
            UIView.animate(withDuration: 0.5) { [weak self] in
                self?.scrollToBottomButton.alpha = scrollView.isNearBottom ? 0 : 1
            } completion: { [weak self] _ in
                self?.scrollToBottomButton.isHidden = scrollView.isNearBottom
            }
        }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        automaticallyScrollsToBottom = false
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard !isSearching else {
            return
        }
        let bottomEdge = scrollView.contentOffset.y + scrollView.frame.size.height
        automaticallyScrollsToBottom = bottomEdge >= scrollView.contentSize.height
    }

    func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
        automaticallyScrollsToBottom = false
        return true
    }
}

// MARK: - Button Actions
extension ConsoleLoggerViewController {
    @objc
    private func didPressPauseButton() {
        Task { @MainActor [weak self] in
            self?.automaticallyScrollsToBottom = !(self?.automaticallyScrollsToBottom ?? false)
            guard self?.automaticallyScrollsToBottom ?? false else { return }
            self?.isSearching = false
            guard let endIndex: String.Index = self?.textView.text.endIndex else {
                return
            }
            self?.textView.scrollRangeToVisible(NSRange(..<endIndex, in: self?.textView.text ?? ""))
        }
    }

    @objc
    private func didPressClearButton() {
        Task { @MainActor [weak self] in
            self?.textView.text = ""
        }
    }

    @objc
    private func didPressShareButton(_ sender: UIView?) {
        // Check for warning skip
        guard !UserDefaults.standard.bool(forKey: Self.SkipWarningDefaultsKey) else {
            shareConsoleLogs(sender: sender)
            return
        }

        // Present Warning
        let alertController = UIAlertController(title: "🚨 CRITICAL ALERT 🚨",
                                                message: "Please ensure that you do not share the output of this feature with anyone that you do not wish to have your potentially sensitive information.\n\nThese logs may, at any time, contain information such as email addresses, passwords, API keys, etc.\n\nIf you are not sure about this, press 'Cancel' below and do not continue. No liability is accepted for damages as a result (both direct and indirect) of misuse and/or distribution of these logs.",
                                                preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "Continue",
                                                style: .destructive,
                                                handler: { _ in
                                                    Task { @MainActor [weak self] in
                                                        self?.shareConsoleLogs(sender: sender)
                                                    }
                                                }))
        alertController.addAction(UIAlertAction(title: "Continue & don't ask again",
                                                style: .default,
                                                handler: { [weak self] _ in
                                                    UserDefaults.standard.set(true, forKey: Self.SkipWarningDefaultsKey)
                                                    Task { @MainActor [weak self] in
                                                        self?.shareConsoleLogs(sender: sender)
                                                    }
                                                }))
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(alertController, animated: true, completion: nil)
    }

    @objc
    private func didPressSearchButton() {
        // Pause automatic scrolling
        automaticallyScrollsToBottom = false
        isSearching = true
    }

    @objc
    private func didPressScrollToBottom() {
        Task { @MainActor [weak self] in
            guard let endIndex: String.Index = self?.textView.text.endIndex else {
                return
            }
            self?.textView.scrollRangeToVisible(NSRange(..<endIndex, in: self?.textView.text ?? ""))
            self?.automaticallyScrollsToBottom = !isSearching
        }
    }
}

// MARK: - Exporting
extension ConsoleLoggerViewController {
    private func shareConsoleLogs(sender: UIView?) {
        Task { @MainActor [weak self] in
            self?.shareLogs(items: [textView.text ?? ""], sender: sender)
        }
    }

    private func shareLogs(items: [String], sender: UIView?) {
        // Make sure that there is something to share.
        guard !items.isEmpty else {
            return
        }

        // Construct and present share sheet
        var applicationActivities: [UIActivity]?
        if AppEnvironment.isSimulator {
            applicationActivities = [SaveToDesktopActivity(title: "Save to desktop") { (sharedItems) in
                    let now = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: "/", with: ":")
                    let filename = "\(UIApplication.shared.appName)_\(now).log"
                    for string in sharedItems as? [String] ?? [] {
                        let homeUser = NSString(string: "~").expandingTildeInPath.split(separator: "/").dropFirst().first ?? "-"
                        let path = "Users/\(homeUser)/Desktop/\(filename)"
                        FileManager.default.createFile(atPath: path, contents: string.data(using: .utf8, allowLossyConversion: true), attributes: nil)
                    }
                }
            ]
        }
        let activityController = UIActivityViewController(activityItems: items, applicationActivities: applicationActivities)
        if let sender = sender {
            activityController.popoverPresentationController?.sourceView = sender
        }
        present(activityController, animated: true)
    }
}

// MARK: - SearchBarDataSource
extension ConsoleLoggerViewController: SearchBarDataSource {
    var searchableString: String? {
        return textView.text
    }
}


// MARK: - SearchBarDelegate
extension ConsoleLoggerViewController: SearchBarDelegate {
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
