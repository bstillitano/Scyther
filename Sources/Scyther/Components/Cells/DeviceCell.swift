//
//  DeviceCell.swift
//  Scyther
//
//  Created by Brandon Stillitano on 16/12/20.
//

#if !os(macOS)
import UIKit

final internal class DeviceTableViewCell: UITableViewCell {

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .subtitle, reuseIdentifier: reuseIdentifier)

        imageView?.contentMode = .scaleAspectFit
        imageView?.layer.cornerRadius = 12.0
        imageView?.layer.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        imageView?.frame = CGRect(x: 0, y: 7.5, width: 60, height: bounds.height - 15)

        guard let imageView = imageView else { return }
        if let textLabel = textLabel {
            self.textLabel?.frame = CGRect(x: imageView.frame.origin.x + imageView.frame.size.width,
                                           y: textLabel.frame.origin.y,
                                           width: bounds.size.width,
                                           height: textLabel.frame.size.height)
        }

        if let detailTextLabel = detailTextLabel {
            self.detailTextLabel?.frame = CGRect(x: imageView.frame.origin.x + imageView.frame.size.width,
                                                 y: detailTextLabel.frame.origin.y,
                                                 width: bounds.size.width,
                                                 height: detailTextLabel.frame.size.height)
        }
    }
}
#endif
