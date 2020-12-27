//
//  DefaultCell.swift
//  Scyther
//
//  Created by Brandon Stillitano on 10/12/20.
//

#if !os(macOS)
import UIKit

final internal class DefaultCell: UITableViewCell {

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .value1, reuseIdentifier: reuseIdentifier)

        textLabel?.numberOfLines = 0
        textLabel?.adjustsFontSizeToFitWidth = false
        detailTextLabel?.adjustsFontSizeToFitWidth = true
        detailTextLabel?.minimumScaleFactor = 2
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
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        /// Update text label constraints
        guard textLabel?.superview != nil else {
            return
        }
        textLabel?.snp.remakeConstraints({ (make) in
            make.top.equalToSuperview().inset(8)
            make.bottom.equalToSuperview().inset(8)
            make.width.lessThanOrEqualTo(160)
            
            /// Set conditional constraints
            if imageView?.image != nil {
                make.left.equalTo(imageView?.snp.right ?? 0).offset(16)
            } else {
                make.left.equalToSuperview().inset(16)
            }
        })
        
        /// Update detail text label constraints
        guard detailTextLabel?.superview != nil else {
            return
        }
        detailTextLabel?.snp.remakeConstraints({ (make) in
            make.top.equalToSuperview().inset(8)
            make.bottom.equalToSuperview().inset(8)
            make.right.equalToSuperview().inset(16)
            make.left.equalTo(textLabel?.snp.right ?? 0).offset(16)
        })
    }
}
#endif
