//
//  File.swift
//
//
//  Created by Brandon Stillitano on 12/2/22.
//

import UIKit

public extension UIScrollView {
    var isNearTop: Bool {
        return contentOffset.y <= verticalOffsetForTop - 48
    }

    var isNearBottom: Bool {
        return contentOffset.y >= (contentSize.height - frame.size.height) - 48
    }

    var verticalOffsetForTop: CGFloat {
        let topInset = contentInset.top
        return -topInset
    }

    var verticalOffsetForBottom: CGFloat {
        let scrollViewHeight = bounds.height
        let scrollContentSizeHeight = contentSize.height
        let bottomInset = contentInset.bottom
        let scrollViewBottomOffset = scrollContentSizeHeight + bottomInset - scrollViewHeight
        return scrollViewBottomOffset
    }
}
