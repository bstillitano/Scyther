//
//  NetworkLogCell.swift
//
//
//  Created by Brandon Stillitano on 25/12/20.
//

import UIKit

class NetworkLogCell: UITableViewCell {

    private let stackView = UIStackView()
    private let sidebarStackView = UIStackView()

    private let ribbonView = UIView()

    private let methodLabel = UILabel()
    private let statusCodeLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView()
    private let durationLabel = UILabel()

    private let urlLabel = UILabel()

    private var timer: Timer?

    // MARK: - Init
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        buildView()
        buildLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Private setup
    private func buildView() {
        backgroundColor = .clear

        stackView.spacing = 4
        stackView.axis = .horizontal
        stackView.distribution = .fill
        stackView.alignment = .fill
        stackView.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 8)
        stackView.isLayoutMarginsRelativeArrangement = true
        contentView.addSubview(stackView)

        ribbonView.backgroundColor = .systemRed
        stackView.addArrangedSubview(ribbonView)

        // Sidebar width = 80
        methodLabel.textAlignment = .center
        methodLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        sidebarStackView.addArrangedSubview(methodLabel)

        activityIndicator.hidesWhenStopped = true
        sidebarStackView.addArrangedSubview(activityIndicator)

        statusCodeLabel.textAlignment = .center
        statusCodeLabel.font = UIFont.preferredFont(forTextStyle: .body)
        sidebarStackView.addArrangedSubview(statusCodeLabel)

        durationLabel.textAlignment = .center
        durationLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        sidebarStackView.addArrangedSubview(durationLabel)

        sidebarStackView.spacing = 4
        sidebarStackView.axis = .vertical
        sidebarStackView.distribution = .fillEqually
        sidebarStackView.alignment = .fill
        sidebarStackView.layoutMargins = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        sidebarStackView.isLayoutMarginsRelativeArrangement = true
        stackView.addArrangedSubview(sidebarStackView)

        urlLabel.minimumScaleFactor = 0.4
        urlLabel.font = UIFont.preferredFont(forTextStyle: .body)
        urlLabel.numberOfLines = 0
        urlLabel.lineBreakMode = .byCharWrapping
        urlLabel.adjustsFontSizeToFitWidth = true
        stackView.addArrangedSubview(urlLabel)

        contentView.translatesAutoresizingMaskIntoConstraints = false
    }

    private func buildLayout() {
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-0-[subview]-8-|", options: .directionLeadingToTrailing, metrics: nil, views: ["subview": stackView]))
        contentView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|-0-[subview]-0-|", options: .directionLeadingToTrailing, metrics: nil, views: ["subview": stackView]))

        // Ribbon width
        NSLayoutConstraint(item: ribbonView, attribute: .width, relatedBy: .equal, toItem: .none, attribute: .notAnAttribute, multiplier: 1, constant: 6).isActive = true

        /// Sidebar width
        NSLayoutConstraint(item: sidebarStackView, attribute: .width, relatedBy: .equal, toItem: .none, attribute: .notAnAttribute, multiplier: 1, constant: 60).isActive = true
    }

    // MARK: - Lifecycle
    override var isHighlighted: Bool {
        didSet {
//            contentView.backgroundColor = (isHighlighted) ? .secondarySystemBackground : .systemBackground
        }
    }

    private lazy var width: NSLayoutConstraint = {
        let width = contentView.widthAnchor.constraint(equalToConstant: bounds.size.width)
        width.isActive = true
        return width
    }()

    override func systemLayoutSizeFitting(_ targetSize: CGSize, withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority, verticalFittingPriority: UILayoutPriority) -> CGSize {
        width.constant = bounds.size.width
        return contentView.systemLayoutSizeFitting(CGSize(width: targetSize.width, height: 1))
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        ribbonView.backgroundColor = .clear
        durationLabel.text = nil
        statusCodeLabel.text = nil
        statusCodeLabel.isHidden = false
        statusCodeLabel.textColor = .black
        methodLabel.text = nil
        urlLabel.text = nil

        timer?.invalidate()
        timer = nil
    }

    // MARK: - Configure
    func configure(with request: NetworkLogRow?) {
        guard let request = request else { return }

        methodLabel.text = request.httpMethod?.uppercased()
        statusCodeLabel.text = (request.httpStatusCode ?? 0 > 0) ? "\(request.httpStatusCode ?? 0)" : "---"
        statusCodeLabel.isHidden = (request.httpStatusCode ?? 0 < 1)
        urlLabel.text = request.httpRequestURL
//        durationLabel.text = (request.duration > 0) ? request.duration.formattedMilliseconds() : "-"

        var statusColor: UIColor = .black
        switch request.httpStatusCode ?? 0 {
        case 100..<200: statusColor = .systemBlue // 1×× Informational
        case 200..<300: statusColor = .systemGreen // 2×× Success
        case 300..<400: statusColor = .systemPurple // 3×× Redirection
        case 400..<500: statusColor = .systemOrange // 4×× Client Error
        case 500..<600: statusColor = .systemRed // 5×× Server Error
        default: break
        }

        ribbonView.backgroundColor = statusColor
        statusCodeLabel.textColor = statusColor

        if request.httpStatusCode ?? 0 > 0 {
            activityIndicator.stopAnimating()

            timer?.invalidate()
            timer = nil
        } else {
            activityIndicator.startAnimating()

            // If we don't already have a duration timer running, start one
            if timer == nil {
                timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true, block: { [weak self] timer in
//                    self?.durationLabel.text = (Date().timeIntervalSince(request.date) * 1000).formattedMilliseconds()
                })
            }
        }
    }
}
