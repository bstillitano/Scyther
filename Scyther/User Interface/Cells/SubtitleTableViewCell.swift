//
//  SubtitleTableViewCell.swift
//  DebugMenu
//
//  Created by Jack Perry on 1/1/20.
//  Copyright © 2020 Jack Perry. All rights reserved.
//

#if !os(macOS)
import UIKit
import Foundation

final internal class SubtitleTableViewCell: UITableViewCell {

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .subtitle, reuseIdentifier: reuseIdentifier)

        textLabel?.adjustsFontSizeToFitWidth = true
        detailTextLabel?.adjustsFontSizeToFitWidth = true

        if #available(iOS 13.0, *) {
            detailTextLabel?.textColor = UIColor.secondaryLabel
        }
        detailTextLabel?.numberOfLines = 0
        detailTextLabel?.textAlignment = .right
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()

        if let detailTextLabel = detailTextLabel {
            self.detailTextLabel?.frame = CGRect(x: detailTextLabel.frame.origin.x, y: detailTextLabel.frame.origin.y,
                                                 width: contentView.frame.size.width - (detailTextLabel.frame.origin.x * 2), height: detailTextLabel.frame.size.height)
        }
    }

    // MARK: - Reuse

    override func prepareForReuse() {
        super.prepareForReuse()

        textLabel?.text = nil
        detailTextLabel?.text = nil
        imageView?.image = nil
    }

}
#endif
