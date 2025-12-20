//
//  File.swift
//  
//
//  Created by Brandon Stillitano on 18/2/21.
//

#if !os(macOS)
import UIKit

protocol TopLevelViewDelegate: AnyObject {
    func topLevelView(topLevelView: TopLevelView, didUpdateVisibility isHidden: Bool)
}

class TopLevelView: UIView {
    // MARK: - Delegate
    weak var delegate: TopLevelViewDelegate?
    
    /// Method that is called after every change of the superview's frame, for example after the device rotation.
    func updateFrame() {
        assert(false, "Should be overriden in a subclass.")
    }
    
    override var isHidden: Bool {
        get {
            return super.isHidden
        }
        set {
            super.isHidden = newValue
            delegate?.topLevelView(topLevelView: self, didUpdateVisibility: newValue)
        }
    }
}
#endif
