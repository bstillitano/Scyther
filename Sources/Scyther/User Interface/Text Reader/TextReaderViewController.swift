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
    
    // MARK: - Data
    var text: String? = nil {
        didSet {
            textView.text = text
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        /// Update navigation bar translucensy to avoid cropping content
        navigationController?.navigationBar.isTranslucent = false
    }
    
    private func setupUI() {
        /// Setup Text View
        textView.font = .systemFont(ofSize: 13.0)
        textView.isEditable = false
        view.addSubview(textView)
    }
    
    private func setupConstraints() {
        /// Setup Text View Constraints
        textView.snp.makeConstraints { (make) in
            make.edges.equalToSuperview()
        }
    }
}
#endif
