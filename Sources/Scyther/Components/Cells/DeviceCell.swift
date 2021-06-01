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
        
        guard let imageView = imageView,
              let textLabel = textLabel,
              let detailTextLabel = detailTextLabel
        else {
            return
        }
        
        imageView.layer.cornerRadius = 12.0
        imageView.layer.masksToBounds = true
        
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            imageView.leftAnchor.constraint(equalTo: contentView.leftAnchor, constant: 16),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 48),
            imageView.heightAnchor.constraint(equalToConstant: 48)
        ])
        
        NSLayoutConstraint.activate([
            textLabel.bottomAnchor.constraint(equalTo: imageView.centerYAnchor),
            textLabel.leftAnchor.constraint(equalTo: imageView.rightAnchor, constant: 16),
            textLabel.rightAnchor.constraint(equalTo: contentView.rightAnchor)
        ])
        
        NSLayoutConstraint.activate([
            detailTextLabel.topAnchor.constraint(equalTo: imageView.centerYAnchor),
            detailTextLabel.leftAnchor.constraint(equalTo: imageView.rightAnchor, constant: 16),
            detailTextLabel.rightAnchor.constraint(equalTo: contentView.rightAnchor)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
    }
}
#endif
