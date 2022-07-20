//
//  NetworkLogCell.swift
//
//
//  Created by Brandon Stillitano on 25/12/20.
//

import UIKit

class NetworkLogCell: UITableViewCell {
    // MARK: - UI Elements
    var statusView: UIView = UIView(frame: .zero)
    var methodLabel: UILabel = UILabel(frame: .zero)
    var responseLabel: UILabel = UILabel(frame: .zero)
    var timeLabel: UILabel = UILabel(frame: .zero)
    var urlLabel: UILabel = UILabel(frame: .zero)

    // MARK: - Constraints
    var statusViewConstraints: [NSLayoutConstraint] = []
    var methodLabelConstraints: [NSLayoutConstraint] = []
    var responseLabelConstraints: [NSLayoutConstraint] = []
    var timeLabelConstraints: [NSLayoutConstraint] = []
    var urlLabelConstraints: [NSLayoutConstraint] = []

    override init(style: UITableViewCellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        /// Setup UI
        setupUI()
        setupConstraints()
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        /// Setup `statusView`
        contentView.addSubview(self.statusView)

        /// Setup `urlLabel`
        urlLabel.font = .systemFont(ofSize: 14)
        urlLabel.numberOfLines = 0
        contentView.addSubview(self.urlLabel)

        /// Setup `methodLabel`
        methodLabel.textAlignment = .center
        methodLabel.font = .boldSystemFont(ofSize: 16)
        contentView.addSubview(self.methodLabel)

        /// Setup `responseLabel`
        responseLabel.textAlignment = .center
        contentView.addSubview(responseLabel)

        /// Setup `timeLabel`
        timeLabel.textAlignment = .center
        timeLabel.font = .systemFont(ofSize: 11)
        timeLabel.numberOfLines = 2
        contentView.addSubview(timeLabel)
    }

    private func setupConstraints() {
        // Set Translations
        statusView.translatesAutoresizingMaskIntoConstraints = false
        methodLabel.translatesAutoresizingMaskIntoConstraints = false
        responseLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        urlLabel.translatesAutoresizingMaskIntoConstraints = false

        // Remove Default Constraints
        NSLayoutConstraint.deactivate(imageView?.constraints ?? [])
        NSLayoutConstraint.deactivate(textLabel?.constraints ?? [])
        NSLayoutConstraint.deactivate(detailTextLabel?.constraints ?? [])
        NSLayoutConstraint.deactivate(textLabel?.constraints ?? [])
        NSLayoutConstraint.deactivate(textLabel?.constraints ?? [])

        // Clear Existing Constraints
        NSLayoutConstraint.deactivate(statusViewConstraints)
        NSLayoutConstraint.deactivate(methodLabelConstraints)
        NSLayoutConstraint.deactivate(responseLabelConstraints)
        NSLayoutConstraint.deactivate(timeLabelConstraints)
        NSLayoutConstraint.deactivate(urlLabelConstraints)
        statusViewConstraints.removeAll()
        methodLabelConstraints.removeAll()
        responseLabelConstraints.removeAll()
        timeLabelConstraints.removeAll()
        urlLabelConstraints.removeAll()

        // Setup Status View Constraints
        statusViewConstraints.append(statusView
            .topAnchor
            .constraint(equalTo: contentView.topAnchor))
        statusViewConstraints.append(statusView
            .bottomAnchor
            .constraint(equalTo: contentView.bottomAnchor))
        statusViewConstraints.append(statusView
            .leadingAnchor
            .constraint(equalTo: contentView.leadingAnchor))
        statusViewConstraints.append(statusView
            .widthAnchor
            .constraint(equalToConstant: 8))

        // Setup Method Label Constraints
        methodLabelConstraints.append(methodLabel
            .topAnchor
            .constraint(equalTo: contentView.topAnchor,
                        constant: 8))
        methodLabelConstraints.append(methodLabel
            .leadingAnchor
            .constraint(equalTo: statusView.trailingAnchor,
                        constant: 8))
        methodLabelConstraints.append(methodLabel
            .widthAnchor
            .constraint(equalToConstant: 48))

        // Setup Response Label Constraints
        responseLabelConstraints.append(responseLabel
            .topAnchor
            .constraint(greaterThanOrEqualTo: methodLabel.bottomAnchor,
                        constant: 8))
        responseLabelConstraints.append(responseLabel
            .leadingAnchor
            .constraint(equalTo: statusView.trailingAnchor,
                        constant: 8))
        responseLabelConstraints.append(responseLabel
            .widthAnchor
            .constraint(equalToConstant: 48))

        // Setup Time Label Constraints
        timeLabelConstraints.append(timeLabel
            .bottomAnchor
            .constraint(equalTo: contentView.bottomAnchor,
                        constant: -8))
        timeLabelConstraints.append(timeLabel
            .widthAnchor
            .constraint(equalToConstant: 48))
        timeLabelConstraints.append(timeLabel
            .leadingAnchor
            .constraint(equalTo: statusView.trailingAnchor,
                        constant: 8))
        timeLabelConstraints.append(timeLabel
            .topAnchor
            .constraint(greaterThanOrEqualTo: responseLabel.bottomAnchor,
                        constant: 8))

        // Setup URL Label Constraints
        urlLabelConstraints.append(urlLabel
            .topAnchor
            .constraint(equalTo: contentView.topAnchor,
                        constant: 8))
        urlLabelConstraints.append(urlLabel
            .bottomAnchor
            .constraint(equalTo: contentView.bottomAnchor,
                        constant: -8))
        urlLabelConstraints.append(urlLabel
            .trailingAnchor
            .constraint(equalTo: contentView.trailingAnchor,
                        constant: -16))
        urlLabelConstraints.append(urlLabel
            .leadingAnchor
            .constraint(equalTo: methodLabel.trailingAnchor,
                        constant: 16))

        // Activate Constraints
        NSLayoutConstraint.activate(statusViewConstraints)
        NSLayoutConstraint.activate(methodLabelConstraints)
        NSLayoutConstraint.activate(responseLabelConstraints)
        NSLayoutConstraint.activate(timeLabelConstraints)
        NSLayoutConstraint.activate(urlLabelConstraints)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        /// Reset constraints
        setupConstraints()
    }

    func configureWithRow(_ row: NetworkLogRow) {
        /// Set text
        responseLabel.text = "\(row.httpStatusCode ?? 0)"
        timeLabel.text = row.httpRequestTime
        urlLabel.text = row.httpRequestURL
        methodLabel.text = row.httpMethod

        /// Set Colors
        responseLabel.textColor = row.httpStatusColor
        statusView.backgroundColor = row.httpStatusColor
    }
}
