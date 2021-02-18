//
//  SliderCell.swift
//  
//
//  Created by Brandon Stillitano on 18/2/21.
//

#if os(iOS)
import UIKit

class SliderCell: UITableViewCell {
    var slider: UISlider = UISlider()
    
    override init(style: UITableViewCellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
    
        /// Setup UI
        textLabel?.adjustsFontSizeToFitWidth = false
        textLabel?.numberOfLines = 0
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupConstraints() {
        let frame = textLabel?.frame ?? .zero
        textLabel?.snp.remakeConstraints({ (make) in
            make.top.equalToSuperview().inset(16)
            make.left.equalToSuperview().inset(16)
            make.right.equalToSuperview().inset(16)
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
        slider = row.slider
        contentView.addSubview(slider)
        
        /// Relayout Constraints
        setupConstraints()
    }
}
#endif
