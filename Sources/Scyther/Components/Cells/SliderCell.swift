//
//  SliderCell.swift
//  
//
//  Created by Brandon Stillitano on 18/2/21.
//

#if os(iOS)
import UIKit

protocol SliderCellDelegate: AnyObject {
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
        guard let textLabel = textLabel else { return }
        
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        sliderValueLabel.translatesAutoresizingMaskIntoConstraints = false
        slider.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            textLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            textLabel.leftAnchor.constraint(equalTo: contentView.leftAnchor, constant: 16),
            textLabel.rightAnchor.constraint(equalTo: contentView.rightAnchor, constant: 16)
        ])
        
        NSLayoutConstraint.activate([
            sliderValueLabel.centerYAnchor.constraint(equalTo: textLabel.centerYAnchor),
            sliderValueLabel.rightAnchor.constraint(equalTo: contentView.rightAnchor, constant: 16)
        ])
        
        NSLayoutConstraint.activate([
            slider.topAnchor.constraint(equalTo: textLabel.topAnchor, constant: 8),
            slider.leftAnchor.constraint(equalTo: contentView.leftAnchor, constant: 16),
            slider.rightAnchor.constraint(equalTo: contentView.rightAnchor, constant: 16),
            slider.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: 16)
        ])
    }

    func configureWithRow(_ row: SliderRow) {
        /// Remove existing slider
        slider.removeFromSuperview()
        sliderValueLabel.removeFromSuperview()
        
        /// Set Delegate
        delegate = row.sliderCellDelegate
        
        /// Setup Slider
        slider = row.slider
        slider.removeTarget(self, action: #selector(sliderValueChanged(_:)), for: .valueChanged)
        slider.addTarget(self, action: #selector(sliderValueChanged(_:)), for: .valueChanged)
        sliderValueLabel = row.sliderValueLabel
        contentView.addSubview(slider)
        contentView.addSubview(sliderValueLabel)
        
        /// Set text
        textLabel?.text = row.text
        sliderValueLabel.text = "\(Int(row.slider.value))"
        sliderValueLabel.font = detailTextLabel?.font ?? .systemFont(ofSize: 16.0)
        sliderValueLabel.textColor = .systemGray
        
        /// Relayout Constraints
        setupConstraints()
    }
    
    @objc
    func sliderValueChanged(_ sender: UISlider?) {
        delegate?.sliderValueChanged(slider: sender, label: sliderValueLabel)
    }
}
#endif
