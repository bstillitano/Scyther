//
//  PreviewableCell.swift
//  
//
//  Created by Brandon Stillitano on 2/2/21.
//

#if os(iOS)
import UIKit

class PreviewableCell: UITableViewCell {
    // MARK: - UI Elements
    var previewView: UIView = UIView(frame: .zero)
    var titleLabel: UILabel = UILabel(frame: .zero)
    var descriptionLabel: UILabel = UILabel(frame: .zero)

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
    
    private func setupConstraints() {
        /// Setup `titleLabel` constraints
        titleLabel.snp.remakeConstraints { (make) in
            make.top.left.right.equalToSuperview().inset(16)
        }
        
        /// Setup `descriptionLabel` constraints
        descriptionLabel.snp.remakeConstraints { (make) in
            make.top.equalTo(titleLabel.snp.bottom).offset(8)
            make.left.right.equalToSuperview().inset(16)
            make.width.equalTo(48)
        }
        
        /// Setup `previewView` constraints
        previewView.snp.remakeConstraints { (make) in
            make.top.equalTo(descriptionLabel.snp.bottom).offset(16)
            make.left.bottom.right.equalToSuperview()
        }
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
#endif
