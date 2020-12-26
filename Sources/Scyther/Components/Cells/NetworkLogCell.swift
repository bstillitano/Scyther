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
    
        contentView.addSubview(self.statusView)

        urlLabel.font = .systemFont(ofSize: 12)
        urlLabel.numberOfLines = 0
        contentView.addSubview(self.urlLabel)

        methodLabel.textAlignment = .center
        methodLabel.font = .boldSystemFont(ofSize: 16)
        contentView.addSubview(self.methodLabel)
        
        responseLabel.textAlignment = .center
        contentView.addSubview(responseLabel)
        
        timeLabel.textAlignment = .center
        contentView.addSubview(timeLabel)
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
            make.top.equalToSuperview()
            make.bottom.equalToSuperview()
            make.left.equalTo(methodLabel.snp.right).offset(16)
            make.right.equalToSuperview().inset(16)
        }
    }

    func configureWithRow(_ row: NetworkLogRow) {
        setURL(row.httpRequestURL ?? "-")
        setStatus(row.httpStatusColor)
        // TODO - Set time intercal
//        setTimeInterval(obj.timeInterval ?? 999)
        setRequestTime(row.httpRequestTime ?? "-")
        setMethod(row.httpMethod ?? "-")
        responseLabel.text = "\(row.httpStatusCode ?? 0)"
        responseLabel.textColor = row.httpStatusColor
        timeLabel.text = row.httpRequestTime
        //TODO - SET ISNEW
        isNewBasedOnDate(Date(timeIntervalSinceNow: 100) as Date? ?? Date())
    }

    func setURL(_ url: String) {
        self.urlLabel.text = url
    }

    func setStatus(_ color: UIColor) {
        self.statusView.backgroundColor = color
    }

    func setRequestTime(_ requestTime: String) {
//        self.requestTimeLabel.text = requestTime
    }

    func setTimeInterval(_ timeInterval: Float) {
        if timeInterval == 999 {
//            self.timeIntervalLabel.text = "-"
        } else {
//            self.timeIntervalLabel.text = NSString(format: "%.2f", timeInterval) as String
        }
    }

    func setMethod(_ method: String) {
        self.methodLabel.text = method
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
