//
//  ScytherPreviewable.swift
//  
//
//  Created by Brandon Stillitano on 2/2/21.
//

#if !os(macOS)
import UIKit

public protocol ScytherPreviewable {
    var previewView: UIView { get set }
    var name: String { get set }
    var description: String { get set }
    var customInsets: UIEdgeInsets { get set }
}
#endif
