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
    let padding: CGFloat = 5
    var urlLabel: UILabel = UILabel(frame: CGRect.zero)
    var statusView: UIView = UIView(frame: CGRect.zero)
    var requestTimeLabel: UILabel = UILabel(frame: CGRect.zero)
    var timeIntervalLabel: UILabel = UILabel(frame: CGRect.zero)
    var typeLabel: UILabel = UILabel(frame: CGRect.zero)
    var methodLabel: UILabel = UILabel(frame: CGRect.zero)
    var leftSeparator: UIView = UIView(frame: CGRect.zero)
    var rightSeparator: UIView = UIView(frame: CGRect.zero)
    var circleView: UIView = UIView(frame: CGRect.zero)

    override init(style: UITableViewCellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = UIColor.white
        selectionStyle = .none

        contentView.addSubview(self.statusView)

        self.requestTimeLabel.textAlignment = .center
        self.requestTimeLabel.textColor = UIColor.white
        self.requestTimeLabel.font = .boldSystemFont(ofSize: 13)
        contentView.addSubview(self.requestTimeLabel)

        self.timeIntervalLabel.textAlignment = .center
        self.timeIntervalLabel.font = .systemFont(ofSize: 12)
        contentView.addSubview(self.timeIntervalLabel)

        self.urlLabel.textColor = .black
        self.urlLabel.font = .systemFont(ofSize: 12)
        self.urlLabel.numberOfLines = 2
        contentView.addSubview(self.urlLabel)

        self.methodLabel.textAlignment = .left
        self.methodLabel.textColor = .systemGray
        self.methodLabel.font = .systemFont(ofSize: 12)
        contentView.addSubview(self.methodLabel)

        self.typeLabel.textColor = .systemGray
        self.typeLabel.font = .systemFont(ofSize: 12)
        contentView.addSubview(self.typeLabel)

        self.circleView.backgroundColor = .systemGray
        self.circleView.layer.cornerRadius = 4
        self.circleView.alpha = 0.2
        contentView.addSubview(self.circleView)

        self.leftSeparator.backgroundColor = UIColor.white
        contentView.addSubview(self.leftSeparator)

        self.rightSeparator.backgroundColor = .lightGray
        contentView.addSubview(self.rightSeparator)
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        self.statusView.frame = CGRect(x: 0, y: 0, width: 50, height: frame.height - 1)

        self.requestTimeLabel.frame = CGRect(x: 0, y: 13, width: statusView.frame.width, height: 14)

        self.timeIntervalLabel.frame = CGRect(x: 0, y: requestTimeLabel.frame.maxY + 5, width: statusView.frame.width, height: 14)

        self.urlLabel.frame = CGRect(x: statusView.frame.maxX + padding, y: 0, width: frame.width - urlLabel.frame.minX - 25 - padding, height: 40)
        self.urlLabel.autoresizingMask = .flexibleWidth

        self.methodLabel.frame = CGRect(x: statusView.frame.maxX + padding, y: urlLabel.frame.maxY - 2, width: 40, height: frame.height - urlLabel.frame.maxY - 2)

        self.typeLabel.frame = CGRect(x: methodLabel.frame.maxX + padding, y: urlLabel.frame.maxY - 2, width: 180, height: frame.height - urlLabel.frame.maxY - 2)

        self.circleView.frame = CGRect(x: self.urlLabel.frame.maxX + 5, y: 17, width: 8, height: 8)

        self.leftSeparator.frame = CGRect(x: 0, y: frame.height - 1, width: self.statusView.frame.width, height: 1)
        self.rightSeparator.frame = CGRect(x: self.leftSeparator.frame.maxX, y: frame.height - 1, width: frame.width - self.leftSeparator.frame.maxX, height: 1)
    }

    func isNew() {
        self.circleView.isHidden = false
    }

    func isOld() {
        self.circleView.isHidden = true
    }

    func configForObject(_ obj: ScytherHTTPModel) {
        setURL(obj.requestURL ?? "-")
        setStatus(obj.responseStatus ?? 999)
        setTimeInterval(obj.timeInterval ?? 999)
        setRequestTime(obj.requestTime ?? "-")
        setType(obj.responseType ?? "-")
        setMethod(obj.requestMethod ?? "-")
        isNewBasedOnDate(obj.responseDate as Date? ?? Date())
    }

    func setURL(_ url: String) {
        self.urlLabel.text = url
    }

    func setStatus(_ status: Int) {
        if status == 999 {
            self.statusView.backgroundColor = .systemGray
            self.timeIntervalLabel.textColor = UIColor.white

        } else if status < 400 {
            self.statusView.backgroundColor = .systemGreen
            self.timeIntervalLabel.textColor = .green

        } else {
            self.statusView.backgroundColor = .systemRed
            self.timeIntervalLabel.textColor = .red
        }
    }

    func setRequestTime(_ requestTime: String) {
        self.requestTimeLabel.text = requestTime
    }

    func setTimeInterval(_ timeInterval: Float) {
        if timeInterval == 999 {
            self.timeIntervalLabel.text = "-"
        } else {
            self.timeIntervalLabel.text = NSString(format: "%.2f", timeInterval) as String
        }
    }

    func setType(_ type: String) {
        self.typeLabel.text = type
    }

    func setMethod(_ method: String) {
        self.methodLabel.text = method
    }

    func isNewBasedOnDate(_ responseDate: Date) {
        //TODO - Implement ???? why??????
        if responseDate.isGreaterThanDate(Date()) {
            self.isNew()
        } else {
            self.isOld()
        }
    }
}
#endif
