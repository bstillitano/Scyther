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
        contentView.addSubview(timeLabel)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        /// Setup `statusView` constraints
        statusView.snp.makeConstraints { (make) in
            make.top.equalToSuperview()
            make.bottom.equalToSuperview()
            make.left.equalToSuperview()
            make.width.equalTo(8)
        }
        
        /// Setup `methodLabel` constraints
        methodLabel.snp.makeConstraints { (make) in
            make.top.equalToSuperview().inset(8)
            make.left.equalTo(statusView.snp.right).offset(8)
            make.width.equalTo(48)
        }
        
        /// Setup `responseLabel` constraints
        responseLabel.snp.makeConstraints { (make) in
            make.top.greaterThanOrEqualTo(methodLabel.snp.bottom).offset(8)
            make.left.equalTo(statusView.snp.right).offset(8)
            make.width.equalTo(48)
        }
        
        /// Setup `timeLabel` constraints
        timeLabel.snp.makeConstraints { (make) in
            make.top.greaterThanOrEqualTo(responseLabel.snp.bottom).offset(8)
            make.left.equalTo(statusView.snp.right).offset(8)
            make.width.equalTo(48)
            make.bottom.equalToSuperview().inset(8)
        }
        
        /// Setup `urlLabel` constraints
        urlLabel.snp.makeConstraints { (make) in
            make.top.equalToSuperview().inset(8)
            make.bottom.equalToSuperview().inset(8)
            make.left.equalTo(methodLabel.snp.right).offset(16)
            make.right.equalToSuperview().inset(16)
        }
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
        
        //TODO - SET ISNEW
        isNewBasedOnDate(Date(timeIntervalSinceNow: 100) as Date? ?? Date())
    }

    func isNewBasedOnDate(_ responseDate: Date) {
        //TODO - Implement ???? why??????
        if responseDate.isGreaterThanDate(Date()) {
//            self.isNew()
        } else {
//            self.isOld()
        }
    }
}
#endif
