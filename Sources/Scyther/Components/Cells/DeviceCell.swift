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
        imageView?.translatesAutoresizingMaskIntoConstraints = false
        
        textLabel?.translatesAutoresizingMaskIntoConstraints = false
        
        detailTextLabel?.translatesAutoresizingMaskIntoConstraints = false
        
        imageView?.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8).isActive = true
        imageView?.leftAnchor.constraint(equalTo: contentView.leftAnchor, constant: 16).isActive = true
        imageView?.bottomAnchor.constraint(equalTo: contentView.bottomAnchor).isActive = true
        imageView?.widthAnchor.constraint(equalToConstant: 48).isActive = true
        imageView?.heightAnchor.constraint(equalToConstant: 48).isActive = true
        
        
        textLabel?.bottomAnchor.constraint(equalTo: imageView?.centerYAnchor ?? NSLayoutYAxisAnchor()).isActive = true
        textLabel?.leftAnchor.constraint(equalTo: imageView?.rightAnchor ?? NSLayoutXAxisAnchor(), constant: 16).isActive = true
        textLabel?.rightAnchor.constraint(equalTo: contentView.rightAnchor).isActive = true

        detailTextLabel?.topAnchor.constraint(equalTo: imageView?.centerYAnchor ?? NSLayoutYAxisAnchor()).isActive = true
        detailTextLabel?.leftAnchor.constraint(equalTo: imageView?.rightAnchor ?? NSLayoutXAxisAnchor(), constant: 16).isActive = true
        detailTextLabel?.rightAnchor.constraint(equalTo: contentView.rightAnchor).isActive = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
    }
}
#endif
