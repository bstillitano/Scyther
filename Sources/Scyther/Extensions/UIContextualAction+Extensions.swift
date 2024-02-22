//
//  File.swift
//  
//
//  Created by Brandon Stillitano on 22/2/2024.
//

import UIKit

extension UIContextualAction {
    internal static func deleteAction(withActionBlock actionBlock: ActionBlock? = nil) -> UIContextualAction {
        let action: UIContextualAction = UIContextualAction(style: .destructive, title: nil, handler: { _, _, _ in
            actionBlock?()
        })
        action.image = UIImage(systemImage: "trash")?.withTintColor(.white)
        return action
    }
}
