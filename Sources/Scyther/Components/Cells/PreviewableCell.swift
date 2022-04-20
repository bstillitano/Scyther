//
//  PreviewableCell.swift
//
//
//  Created by Brandon Stillitano on 2/2/21.
//

import UIKit

class PreviewableCell: UITableViewCell {
    // MARK: - UI Elements
    var previewView: UIView = UIView(frame: .zero)
    var titleLabel: UILabel = UILabel(frame: .zero)
    var descriptionLabel: UILabel = UILabel(frame: .zero)

    // MARK: - Constraints
    var previewViewConstraints: [NSLayoutConstraint] = []
    var titleLabelConstraints: [NSLayoutConstraint] = []
    var descriptionLabelConstraints: [NSLayoutConstraint] = []

    override init(style: UITableViewCellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        /// Setup UI
        setupUI()
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        /// Setup `titlelabel`
        titleLabel.font = .boldSystemFont(ofSize: 14)
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .left
        contentView.addSubview(titleLabel)

        /// Setup `descriptionLabel`
        descriptionLabel.font = .systemFont(ofSize: 12)
        descriptionLabel.numberOfLines = 0
        descriptionLabel.textAlignment = .left
        contentView.addSubview(descriptionLabel)

        /// Setup `previewView`
        contentView.addSubview(previewView)
    }

    private func setupConstraints() { // Set Translations
        previewView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false

        // Remove Default Constraints
        NSLayoutConstraint.deactivate(imageView?.constraints ?? [])
        NSLayoutConstraint.deactivate(textLabel?.constraints ?? [])
        NSLayoutConstraint.deactivate(detailTextLabel?.constraints ?? [])

        // Clear Existing Constraints
        NSLayoutConstraint.deactivate(previewViewConstraints)
        NSLayoutConstraint.deactivate(titleLabelConstraints)
        NSLayoutConstraint.deactivate(descriptionLabelConstraints)
        previewViewConstraints.removeAll()
        titleLabelConstraints.removeAll()
        descriptionLabelConstraints.removeAll()

        // Setup Title Label Constraints
        titleLabelConstraints.append(titleLabel
            .topAnchor
            .constraint(equalTo: contentView.topAnchor,
                        constant: 16))
        titleLabelConstraints.append(titleLabel
            .trailingAnchor
            .constraint(equalTo: contentView.trailingAnchor,
                        constant: -16))
        titleLabelConstraints.append(titleLabel
            .leadingAnchor
            .constraint(equalTo: contentView.leadingAnchor,
                        constant: 16))

        // Setup Description Label Constraints
        descriptionLabelConstraints.append(descriptionLabel
            .topAnchor
            .constraint(equalTo: titleLabel.bottomAnchor,
                        constant: 8))
        descriptionLabelConstraints.append(descriptionLabel
            .trailingAnchor
            .constraint(equalTo: contentView.trailingAnchor,
                        constant: -16))
        descriptionLabelConstraints.append(descriptionLabel
            .leadingAnchor
            .constraint(equalTo: contentView.leadingAnchor,
                        constant: 16))
        descriptionLabelConstraints.append(descriptionLabel
            .widthAnchor
            .constraint(equalToConstant: 48))

        // Setup Preview View Constraints
        previewViewConstraints.append(previewView
            .topAnchor
            .constraint(equalTo: descriptionLabel.bottomAnchor,
                        constant: 16))
        previewViewConstraints.append(previewView
            .leadingAnchor
            .constraint(equalTo: contentView.leadingAnchor))
        previewViewConstraints.append(previewView
            .trailingAnchor
            .constraint(equalTo: contentView.trailingAnchor))
        previewViewConstraints.append(previewView
            .bottomAnchor
            .constraint(equalTo: contentView.bottomAnchor))

        // Activate Constraints
        NSLayoutConstraint.activate(previewViewConstraints)
        NSLayoutConstraint.activate(titleLabelConstraints)
        NSLayoutConstraint.activate(descriptionLabelConstraints)
    }

    func configureWithRow(_ row: PreviewableRow) {
        /// Remove existing preview
        previewView.removeFromSuperview()

        /// Set text
        titleLabel.text = row.text
        descriptionLabel.text = row.detailText

        /// Setup preview
        previewView = row.previewView
        contentView.addSubview(previewView)

        /// Relayout Constraints
        setupConstraints()
    }
}
