//
//  SectionHeaderView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 8/12/20.
//

import UIKit

class SectionHeaderView: UIView {
    //UI Elements
    private var label: UILabel = UILabel()
    var imageView: UIImageView = UIImageView()

    //Data
    var text: String? = nil {
        didSet {
            label.text = text
            setConstraints()
        }
    }
    var textColor: UIColor? = nil {
        didSet {
            label.textColor = textColor ?? .systemGray
            setConstraints()
        }
    }
    var image: UIImage? = nil {
        didSet {
            imageView.image = image?.withRenderingMode(.alwaysTemplate)
            setConstraints()
        }
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        //Setup Interface
        self.setupUI()
    }

    private func setupUI() {
        //Setup Image View
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .systemGreen
        self.addSubview(imageView)

        //Setup Text Label
        label.font = .systemFont(ofSize: 16.0)
        label.numberOfLines = 0
        label.textAlignment = .left
        self.addSubview(label)
    }

    private func setConstraints() {
        //Setup Image View Constraints
        imageView.snp.remakeConstraints { (make) in
            make.left.equalToSuperview()
            make.width.height.equalTo(image == nil ? 0 : 24)

            //Add Conditional Y Constraint
            if text == nil {
                make.top.bottom.equalToSuperview()
            } else {
                make.centerY.equalTo(label.snp.centerY)
            }
        }
        imageView.isHidden = image == nil

        //Setup Text Label Constraints
        label.snp.remakeConstraints { (make) in
            make.right.equalToSuperview()
            make.top.equalToSuperview()

            //Add Conditional Left Constriants
            if image == nil {
                make.left.equalToSuperview()
            } else {
                make.left.equalTo(imageView.snp.right).offset(16)
            }

            //Add Conditional Bottom Constriants
            if text != nil {
                make.bottom.equalToSuperview()
            }
        }
        label.isHidden = text == nil
    }
}
