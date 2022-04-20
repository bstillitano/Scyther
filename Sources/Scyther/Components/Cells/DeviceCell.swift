//
//  DeviceCell.swift
//  Scyther
//
//  Created by Brandon Stillitano on 16/12/20.
//

import UIKit

final internal class DeviceTableViewCell: UITableViewCell {
    // MARK: - Constraints
    var imageViewConstraints: [NSLayoutConstraint] = []
    var textLabelConstraints: [NSLayoutConstraint] = []
    var detailTextLabelConstraints: [NSLayoutConstraint] = []

    // MARK: - Lifecycle
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .subtitle, reuseIdentifier: reuseIdentifier)

        imageView?.layer.cornerRadius = 12.0
        imageView?.layer.masksToBounds = true

        setupConstraints()
    }

    private func setupConstraints() {
        // Set Translations
        imageView?.translatesAutoresizingMaskIntoConstraints = false
        textLabel?.translatesAutoresizingMaskIntoConstraints = false
        detailTextLabel?.translatesAutoresizingMaskIntoConstraints = false

        // Remove Default Constraints
        NSLayoutConstraint.deactivate(imageView?.constraints ?? [])
        NSLayoutConstraint.deactivate(textLabel?.constraints ?? [])
        NSLayoutConstraint.deactivate(detailTextLabel?.constraints ?? [])

        // Clear Existing Constraints
        NSLayoutConstraint.deactivate(imageViewConstraints)
        NSLayoutConstraint.deactivate(textLabelConstraints)
        NSLayoutConstraint.deactivate(detailTextLabelConstraints)
        imageViewConstraints.removeAll()
        textLabelConstraints.removeAll()
        detailTextLabelConstraints.removeAll()

        // Setup Image View Constraints
        imageViewConstraints.append(imageView?
            .topAnchor
            .constraint(equalTo: topAnchor,
                        constant: 8) ?? NSLayoutConstraint())
        imageViewConstraints.append(imageView?
            .bottomAnchor
            .constraint(lessThanOrEqualTo: bottomAnchor) ?? NSLayoutConstraint())
        imageViewConstraints.append(imageView?
            .leadingAnchor
            .constraint(equalTo: leadingAnchor,
                        constant: 16) ?? NSLayoutConstraint())
        imageViewConstraints.append(imageView?
            .widthAnchor
            .constraint(equalToConstant: 48) ?? NSLayoutConstraint())
        imageViewConstraints.append(imageView?
            .heightAnchor
            .constraint(equalToConstant: 48) ?? NSLayoutConstraint())

        // Setup Text Label Constraints
        textLabelConstraints.append(textLabel?
            .bottomAnchor
            .constraint(equalTo: imageView?.centerYAnchor ?? centerYAnchor) ?? NSLayoutConstraint())
        textLabelConstraints.append(textLabel?
            .leadingAnchor
            .constraint(equalTo: imageView?.trailingAnchor ?? leadingAnchor,
                        constant: 16) ?? NSLayoutConstraint())
        textLabelConstraints.append(textLabel?
            .trailingAnchor
            .constraint(equalTo: trailingAnchor) ?? NSLayoutConstraint())

        // Setup Detail Text Label Constraints
        detailTextLabelConstraints.append(detailTextLabel?
            .topAnchor
            .constraint(equalTo: imageView?.centerYAnchor ?? centerYAnchor) ?? NSLayoutConstraint())
        detailTextLabelConstraints.append(detailTextLabel?
            .leadingAnchor
            .constraint(equalTo: imageView?.trailingAnchor ?? leadingAnchor,
                        constant: 16) ?? NSLayoutConstraint())
        detailTextLabelConstraints.append(detailTextLabel?
            .trailingAnchor
            .constraint(equalTo: trailingAnchor) ?? NSLayoutConstraint())

        // Activate Constraints
        NSLayoutConstraint.activate(imageViewConstraints)
        NSLayoutConstraint.activate(textLabelConstraints)
        NSLayoutConstraint.activate(detailTextLabelConstraints)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
