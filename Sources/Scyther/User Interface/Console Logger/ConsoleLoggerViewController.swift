//
//  File.swift
//  
//
//  Created by Brandon Stillitano on 18/1/21.
//

#if !os(macOS)
import UIKit

class ConsoleLoggerViewController: UIViewController {
    // MARK: - UI Elements
    private var textView: UITextView = UITextView()
    
    // MARK: - Data
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        /// Setup Interface
        setupUI()
        setupConstraints()
    }
    
    private func setupUI() {
        /// Setup background colour
        view.backgroundColor = .black
    }
    
    private func setupConstraints() {
        
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
}
#endif
