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
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            titleLabel.leftAnchor.constraint(equalTo: contentView.leftAnchor, constant: 16),
            titleLabel.rightAnchor.constraint(equalTo: contentView.rightAnchor, constant: 16)
        ])
        
        /// Setup `descriptionLabel` constraints
        NSLayoutConstraint.activate([
            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.topAnchor, constant: 8),
            descriptionLabel.leftAnchor.constraint(equalTo: contentView.leftAnchor, constant: 16),
            descriptionLabel.rightAnchor.constraint(equalTo: contentView.rightAnchor, constant: 16),
            descriptionLabel.widthAnchor.constraint(equalToConstant: 48)
        ])
        
        /// Setup `previewView` constraints
        NSLayoutConstraint.activate([
            descriptionLabel.topAnchor.constraint(equalTo: descriptionLabel.topAnchor),
            descriptionLabel.leftAnchor.constraint(equalTo: contentView.leftAnchor),
            descriptionLabel.rightAnchor.constraint(equalTo: contentView.rightAnchor),
            descriptionLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
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
