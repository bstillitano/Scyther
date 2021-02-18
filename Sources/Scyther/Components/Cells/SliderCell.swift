//
//  SliderCell.swift
//  
//
//  Created by Brandon Stillitano on 18/2/21.
//

#if os(iOS)
import UIKit

class SliderCell: UITableViewCell {
    // MARK: - UI Elements
    var slider: UISlider = UISlider()

    override init(style: UITableViewCellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
    
        /// Setup UI
        textLabel?.adjustsFontSizeToFitWidth = false
        textLabel?.numberOfLines = 0
        setupUI()
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        /// Setup `slider`
        slider.minimumValue = 1
        slider.maximumValue = 100
        slider.isContinuous = true
        contentView.addSubview(slider)
    }
    
    private func setupConstraints() {
        let frame = textLabel?.frame ?? .zero
        textLabel?.snp.remakeConstraints({ (make) in
            make.top.equalTo(frame.origin.y)
            make.left.equalTo(frame.origin.x)
            make.right.equalToSuperview().inset(frame.origin.x)
        })
        
        slider.snp.remakeConstraints { (make) in
            make.top.equalTo(textLabel?.snp.bottom ?? 0).offset(8)
            make.left.equalToSuperview().inset(16)
            make.right.equalToSuperview().inset(16)
            make.bottom.equalToSuperview().inset(16)
        }
    }

    func configureWithRow(_ row: SliderRow) {
        /// Remove existing slider
        slider.removeFromSuperview()

        /// Set text
        textLabel?.text = row.text
        
        /// Setup Slider
        contentView.addSubview(slider)
        
        /// Relayout Constraints
        setupConstraints()
    }
}
#endif
