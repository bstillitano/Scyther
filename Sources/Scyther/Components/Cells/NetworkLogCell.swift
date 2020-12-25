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

        urlLabel.textColor = .black
        urlLabel.font = .systemFont(ofSize: 12)
        urlLabel.numberOfLines = 0
        contentView.addSubview(self.urlLabel)

        methodLabel.textAlignment = .center
        methodLabel.font = .boldSystemFont(ofSize: 16)
        contentView.addSubview(self.methodLabel)
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        statusView.frame = CGRect(x: 0, y: 0, width: 8, height: frame.height - 1)
        methodLabel.frame = CGRect(x: 16, y: 8, width: 48, height: 16)
    }

    func configureWithRow(_ row: NetworkLogRow) {
        setURL(row.httpRequestURL ?? "-")
        setStatus(row.httpStatusColor)
        // TODO - Set time intercal
//        setTimeInterval(obj.timeInterval ?? 999)
        setRequestTime(row.httpRequestTime ?? "-")
        setMethod(row.httpMethod ?? "-")
        
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
