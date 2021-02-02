//
//  ScytherPreviewable.swift
//  
//
//  Created by Brandon Stillitano on 2/2/21.
//

#if !os(macOS)
import UIKit

public protocol ScytherPreviewable {
    var previewView: UIView { get }
    var name: String { get}
    var details: String { get }
    var customInsets: UIEdgeInsets? { get }
}
#endif
