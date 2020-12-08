//
//  SectionHeaderCell.swift
//  Scyther
//
//  Created by Brandon Stillitano on 8/12/20.
//

import DTModelStorage
import UIKit

class SectionHeaderCell: UITableViewCell, ModelTransfer {
    //UI Elements
    private var headerView: SectionHeaderView = SectionHeaderView()

    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    override public func awakeFromNib() {
        super.awakeFromNib()
        commonInit()
    }

    public override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        commonInit()
    }

    private func commonInit() {
        //Setup Label
        self.contentView.addSubview(headerView)
        headerView.snp.makeConstraints { (make) in
            make.edges.equalToSuperview()
        }

        //Setup Cell Style
        self.selectionStyle = .none
        self.separatorInset = UIEdgeInsets(top: 0,
                                           left: 0,
                                           bottom: 0,
                                           right: .greatestFiniteMagnitude)

        //Layout Subviews
        self.layoutIfNeeded()
    }

    public func update(with model: SectionHeaderConfigObject) {
        //Setup Label
        headerView.text = model.text
        headerView.image = model.icon
        headerView.textColor = model.textColor

        //Setup Constraints
        if let insets: Spacing = model.customInsets {
            headerView.snp.remakeConstraints { (make) in
                make.top.equalToSuperview().inset(insets.top)
                make.left.equalToSuperview().inset(insets.left)
                make.bottom.equalToSuperview().inset(insets.bottom)
                make.right.equalToSuperview().inset(insets.right)
            }
        }

        //Layout Subviews
        self.layoutIfNeeded()
    }
}
