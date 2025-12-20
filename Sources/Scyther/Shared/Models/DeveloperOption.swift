//
//  File.swift
//
//
//  Created by Brandon Stillitano on 12/2/21.
//

#if !os(macOS)
import UIKit

/// Different types of developer options, controls how a developer option is represented in the main menu.
public enum DeveloperOptionType: CaseIterable {
    case viewController
    case value
}

public struct DeveloperOption {
    public init(name: String, value: String, icon: UIImage? = nil) {
        self.type = .value
        self.name = name
        self.value = value
        self.icon = icon
    }
    
    public init(name: String, icon: UIImage? = nil, viewController: UIViewController? = nil) {
        self.type = .viewController
        self.name = name
        self.icon = icon
        self.viewController = viewController
    }
    
    internal var type: DeveloperOptionType
    public var name: String
    public var value: String?
    public var icon: UIImage?
    public var viewController: UIViewController?
}
#endif
