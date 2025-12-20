//
//  ScytherPreviewable.swift
//  
//
//  Created by Brandon Stillitano on 2/2/21.
//

#if !os(macOS)
import UIKit

@objc
public protocol ScytherPreviewable: AnyObject {
    static var previewView: UIView { get }
    static var name: String { get}
    static var details: String { get }
}
#endif
