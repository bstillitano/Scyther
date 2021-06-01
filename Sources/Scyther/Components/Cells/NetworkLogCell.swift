//
//  NetworkLogCell.swift
//
//
//  Created by Brandon Stillitano on 25/12/20.
//

#if os(iOS)
import UIKit

class NetworkLogCell: UITableViewCell {
    // MARK: - UI Elements
    var statusView: UIView = UIView(frame: .zero)
    var methodLabel: UILabel = UILabel(frame: .zero)
    var responseLabel: UILabel = UILabel(frame: .zero)
    var timeLabel: UILabel = UILabel(frame: .zero)
    var urlLabel: UILabel = UILabel(frame: .zero)

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
        statusView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(self.statusView)

        /// Setup `urlLabel`
        urlLabel.font = .systemFont(ofSize: 14)
        urlLabel.numberOfLines = 0
        urlLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(self.urlLabel)

        /// Setup `methodLabel`
        methodLabel.textAlignment = .center
        methodLabel.font = .boldSystemFont(ofSize: 16)
        methodLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(self.methodLabel)
        
        /// Setup `responseLabel`
        responseLabel.textAlignment = .center
        responseLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(responseLabel)
        
        /// Setup `timeLabel`
        timeLabel.textAlignment = .center
        timeLabel.font = .systemFont(ofSize: 11)
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(timeLabel)
    }
    
    private func setupConstraints() {
        /// Setup `statusView` constraints
        NSLayoutConstraint.activate([
            statusView.topAnchor.constraint(equalTo: contentView.topAnchor),
            statusView.leftAnchor.constraint(equalTo: contentView.leftAnchor),
            statusView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            statusView.widthAnchor.constraint(equalToConstant: 8)
        ])
        
        /// Setup `methodLabel` constraints
        NSLayoutConstraint.activate([
            methodLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            methodLabel.leftAnchor.constraint(equalTo: statusView.rightAnchor, constant: 8),
            methodLabel.widthAnchor.constraint(equalToConstant: 48)
        ])
        
        /// Setup `responseLabel` constraints
        NSLayoutConstraint.activate([
            responseLabel.topAnchor.constraint(greaterThanOrEqualTo: methodLabel.bottomAnchor, constant: -8),
            responseLabel.leftAnchor.constraint(equalTo: statusView.rightAnchor, constant: 8),
            responseLabel.widthAnchor.constraint(equalToConstant: 48)
        ])
        
        /// Setup `timeLabel` constraints
        NSLayoutConstraint.activate([
            timeLabel.topAnchor.constraint(greaterThanOrEqualTo: responseLabel.bottomAnchor, constant: -8),
            timeLabel.leftAnchor.constraint(equalTo: statusView.rightAnchor, constant: 8),
            timeLabel.widthAnchor.constraint(equalToConstant: 48),
            timeLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        
        /// Setup `urlLabel` constraints
        NSLayoutConstraint.activate([
            urlLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            urlLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            urlLabel.leftAnchor.constraint(equalTo: methodLabel.rightAnchor, constant: 8),
            urlLabel.rightAnchor.constraint(equalTo: contentView.rightAnchor, constant: -16),
        ])
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
#endif
