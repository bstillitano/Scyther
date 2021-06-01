//
//  TextReaderViewController.swift
//  
//
//  Created by Brandon Stillitano on 28/12/20.
//

#if os(iOS)
import UIKit

class TextReaderViewController: UIViewController {
    // MARK: - UI Elements
    var textView: UITextView = UITextView()
    var shareButton: UIBarButtonItem?

    // MARK: - Data
    var text: String? = nil {
        didSet {
            textView.text = text
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        /// Setup interface
        setupUI()
        setupConstraints()
        
        /// Setup Share Button
        shareButton = UIBarButtonItem(barButtonSystemItem: .action,
                                      target: self,
                                      action: #selector(shareText))
        navigationItem.setRightBarButton(shareButton, animated: true)
    }
    
    private func setupUI() {
        /// Setup Text View
        textView.font = .systemFont(ofSize: 13.0)
        textView.isEditable = false
        textView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textView)
    }
    
    private func setupConstraints() {
        /// Setup Text View Constraints
        NSLayoutConstraint.activate([
            textView.leftAnchor.constraint(equalTo: view.leftAnchor),
            textView.rightAnchor.constraint(equalTo: view.rightAnchor),
            textView.topAnchor.constraint(equalTo: view.topAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    @objc
    private func shareText() {
        let viewController = UIActivityViewController(activityItems: [text ?? ""],
                                                      applicationActivities: nil)
        self.present(viewController, animated: true)
    }
}
#endif
