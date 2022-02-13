//
//  File.swift
//
//
//  Created by Brandon Stillitano on 12/2/22.
//

import UIKit

public extension UIScrollView {
    var isNearBottom: Bool {
        return contentOffset.y >= (contentSize.height - frame.size.height) - 48
    }
}
