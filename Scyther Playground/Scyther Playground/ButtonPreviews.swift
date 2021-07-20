//
//  ButtonPreviews.swift
//  Scyther Playground
//
//  Created by Brandon Stillitano on 18/2/21.
//

import UIKit
import Scyther

class PrimaryButtonPreview: Button {}
extension PrimaryButtonPreview: ScytherPreviewable {
    static var previewView: UIView {
        let button: Button = Button(.primary)
        button.setTitle("Do something", for: .normal)
        button.setImage(UIImage(systemImage: "cart.circle.fill"))
        return button
    }
    
    static var name: String {
        return "Button - Primary"
    }
    
    static var details: String {
        return "A button used to indicate a primary action"
    }
}

class SecondaryButtonPreview: Button {}
extension SecondaryButtonPreview: ScytherPreviewable {
    static var previewView: UIView {
        let button: Button = Button(.secondary)
        button.setTitle("Do something", for: .normal)
        button.setImage(UIImage(systemImage: "cart.circle.fill"))
        return button
    }
    
    static var name: String {
        return "Button - Secondary"
    }
    
    static var details: String {
        return "A button used to indicate a secondary action"
    }
}

class PlainButtonPreview: Button {}
extension PlainButtonPreview: ScytherPreviewable {
    static var previewView: UIView {
        let button: Button = Button(.plain)
        button.setTitle("Do something", for: .normal)
        button.setImage(UIImage(systemImage: "cart.circle.fill"))
        return button
    }
    
    static var name: String {
        return "Button - Plain"
    }
    
    static var details: String {
        return "A button used to indicate a primary action with plain text"
    }
}

class PlainLeftButtonPreview: Button {}
extension PlainLeftButtonPreview: ScytherPreviewable {
    static var previewView: UIView {
        let button: Button = Button(.plainLeft)
        button.setTitle("Do something", for: .normal)
        button.setImage(UIImage(systemImage: "cart.circle.fill"))
        return button
    }
    
    static var name: String {
        return "Button - Plain Left"
    }
    
    static var details: String {
        return "A button used to indicate a primary action with plain and left aligned text"
    }
}
