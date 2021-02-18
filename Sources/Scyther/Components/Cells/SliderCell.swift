//
//  SliderCell.swift
//  
//
//  Created by Brandon Stillitano on 18/2/21.
//

#if os(iOS)
import UIKit

protocol SliderCellDelegate: class {
    func sliderValueChanged(slider: UISlider?, label: UILabel)
}

class SliderCell: UITableViewCell {
    // MARK: - UI Elements
    var slider: UISlider = UISlider()
    var sliderValueLabel: UILabel = UILabel()
    
    // MARK: - Delegate
    weak var delegate: SliderCellDelegate?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .value1, reuseIdentifier: reuseIdentifier)
    
        /// Setup UI
        textLabel?.adjustsFontSizeToFitWidth = false
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupConstraints() {
        textLabel?.snp.remakeConstraints({ (make) in
            make.top.equalToSuperview().inset(16)
            make.left.equalToSuperview().inset(16)
            make.right.equalToSuperview().inset(16)
        })
        
        sliderValueLabel.snp.remakeConstraints({ (make) in
            make.centerY.equalTo(textLabel?.snp.centerY ?? 0)
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
        sliderValueLabel.removeFromSuperview()
        
        /// Set text
        textLabel?.text = row.text
        sliderValueLabel.text = "\(Int(row.slider.value))"
        sliderValueLabel.font = detailTextLabel?.font
        sliderValueLabel.textColor = detailTextLabel?.textColor
            
        /// Setup Slider
        slider = row.slider
        slider.removeTarget(self, action: #selector(sliderValueChanged(_:)), for: .valueChanged)
        slider.addTarget(self, action: #selector(sliderValueChanged(_:)), for: .valueChanged)
        sliderValueLabel = row.sliderValueLabel
        contentView.addSubview(slider)
        contentView.addSubview(sliderValueLabel)
        
        /// Relayout Constraints
        setupConstraints()
    }
    
    @objc
    func sliderValueChanged(_ sender: UISlider?) {
        delegate?.sliderValueChanged(slider: sender, label: sliderValueLabel)
    }
}
#endif
