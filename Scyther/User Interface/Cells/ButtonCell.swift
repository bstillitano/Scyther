//
//  ButtonCell.swift
//  Scyther
//
//  Created by Brandon Stillitano on 11/12/20.
//

#if !os(macOS)
import UIKit
import Foundation

final internal class ButtonCell: UITableViewCell {

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .default, reuseIdentifier: reuseIdentifier)

        textLabel?.textAlignment = .center
        textLabel?.textColor = UIColor.systemBlue
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        textLabel?.textAlignment = .center
        textLabel?.textColor = UIColor.systemBlue
        textLabel?.font = textLabel?.font.bold
        textLabel?.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        accessoryType = .none
        imageView?.image = nil
    }

}
#endif
