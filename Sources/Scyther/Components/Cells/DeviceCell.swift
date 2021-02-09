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

        imageView?.layer.cornerRadius = 12.0
        imageView?.layer.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        imageView?.snp.remakeConstraints({ (make) in
            make.top.bottom.equalToSuperview().inset(8)
            make.left.equalToSuperview()
            make.width.height.equalTo(60)
        })

        textLabel?.snp.remakeConstraints({ (make) in
            make.top.equalTo(textLabel?.frame.origin.y ?? 0)
            make.left.equalTo(imageView?.snp.right ?? 0)
            make.right.equalToSuperview()
        })
        
        detailTextLabel?.snp.remakeConstraints({ (make) in
            make.top.equalTo(detailTextLabel?.frame.origin.y ?? 0)
            make.left.equalTo(imageView?.snp.right ?? 0)
            make.right.equalToSuperview()
            make.bottom.equalToSuperview()
        })
    }
}
#endif
