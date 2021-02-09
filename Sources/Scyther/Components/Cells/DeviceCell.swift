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
        
        imageView?.snp.remakeConstraints({ (make) in
            make.top.bottom.equalToSuperview().inset(8)
            make.left.equalToSuperview().inset(8)
            make.width.equalTo(48)
            make.height.equalTo(48)
        })

        textLabel?.snp.remakeConstraints({ (make) in
            make.bottom.equalTo(contentView.snp.centerY)
            make.left.equalTo(imageView?.snp.right ?? 0).offset(8)
            make.right.equalToSuperview()
        })
        
        detailTextLabel?.snp.remakeConstraints({ (make) in
            make.top.equalTo(contentView.snp.centerY)
            make.left.equalTo(imageView?.snp.right ?? 0).offset(8)
            make.right.equalToSuperview()
        })
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

    }
}
#endif
