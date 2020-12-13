//
//  CheckmarkCell.swift
//  Scyther
//
//  Created by Brandon Stillitano on 13/12/20.
//

#if !os(macOS)
import UIKit

final internal class CheckmarkCell: UITableViewCell {

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .value1, reuseIdentifier: reuseIdentifier)

        textLabel?.numberOfLines = 0
        textLabel?.adjustsFontSizeToFitWidth = true
        detailTextLabel?.adjustsFontSizeToFitWidth = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        accessoryType = .none
        textLabel?.text = nil
        detailTextLabel?.text = nil
        imageView?.image = nil
    }
}
#endif
