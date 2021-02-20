//
//  SubtitleCell.swift
//  Scyther
//
//  Created by Brandon Stillitano on 15/12/20.
//

#if !os(macOS)
import UIKit

final internal class SubtitleCell: UITableViewCell {

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .subtitle, reuseIdentifier: reuseIdentifier)

        textLabel?.numberOfLines = 0
        textLabel?.adjustsFontSizeToFitWidth = false
        detailTextLabel?.adjustsFontSizeToFitWidth = false
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
