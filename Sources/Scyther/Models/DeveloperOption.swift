//
//  File.swift
//
//
//  Created by Brandon Stillitano on 12/2/21.
//

#if !os(macOS)
import UIKit

public struct DeveloperOption {
    public init() { }
    
    public var name: String?
    public var icon: UIImage?
    public var viewController: UIViewController?
}
#endif
